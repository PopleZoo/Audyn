// LibtorrentWrapper.cpp  —  build‑able with clang++ ‑std=c++17
// -------------------------------------------------------------

#include <jni.h>
#include <string>
#include <iostream>
#include <fstream>
#include <memory>
#include <mutex>
#include <vector>
#include <sstream>
#include <cstdlib>

#include <android/log.h>

#include <libtorrent/kademlia/item.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/alert_types.hpp>

#if __has_include(<filesystem>)
#include <filesystem>
namespace fs = std::filesystem;
#else
#include <experimental/filesystem>
namespace fs = std::experimental::filesystem;
#endif

#define LOG_TAG "LibtorrentWrapper"
#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO , LOG_TAG, __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__))

using namespace lt;

// ──────────────────────────────────────────────────────────────
//  Global session (uTP‑only, no public DHT/trackers)
// ──────────────────────────────────────────────────────────────
static std::unique_ptr<session>  g_ses;
static std::mutex                g_mtx;

static session& get_session()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (g_ses) return *g_ses;

    settings_pack sp;
    sp.set_int(settings_pack::alert_mask, alert::error_notification | alert::status_notification);

    // uTP only
    sp.set_bool(settings_pack::enable_outgoing_tcp , false);
    sp.set_bool(settings_pack::enable_incoming_tcp , false);
    sp.set_bool(settings_pack::enable_outgoing_utp , true );
    sp.set_bool(settings_pack::enable_incoming_utp , true );

    // disable external discovery
    sp.set_bool(settings_pack::enable_dht  , false);
    sp.set_bool(settings_pack::enable_lsd  , false);
    sp.set_bool(settings_pack::enable_upnp , false);
    sp.set_bool(settings_pack::enable_natpmp,false);

    sp.set_str(settings_pack::listen_interfaces, "0.0.0.0:6881");

    g_ses = std::make_unique<session>(sp);
    LOGI("[Native] libtorrent %s session started", LIBTORRENT_VERSION);
    return *g_ses;
}

// ──────────────────────────────────────────────────────────────
//  Utility helpers
// ──────────────────────────────────────────────────────────────
static std::string to_hex_str(const sha1_hash& h) { return lt::aux::to_hex(h); }

static sha1_hash hex_to_sha1(const std::string& hex)
{
    sha1_hash out;
    if (!lt::aux::from_hex(hex, out.data())) throw std::runtime_error("bad hex");
    return out;
}

static std::string info_hash_from_torrent(const std::string& path)
{
    std::ifstream in(path, std::ios::binary);
    if (!in) return "";
    std::vector<char> buf{ std::istreambuf_iterator<char>(in), {} };
    error_code ec;
    bdecode_node node = bdecode(buf, ec);
    if (ec) return "";
    auto ti = std::make_shared<torrent_info>(node, ec);
    if (ec) return "";
    return to_hex_str(ti->info_hash());
}

// ──────────────────────────────────────────────────────────────
//  JNI EXPORTS
// ──────────────────────────────────────────────────────────────
extern "C" {

JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getVersion(JNIEnv* env, jobject)
{
    std::string v = "libtorrent " + std::string{LIBTORRENT_VERSION};
    return env->NewStringUTF(v.c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_addTorrent(JNIEnv* env, jobject,
                                                    jstring jTorrentFile, jstring jSavePath,
                                                    jboolean seedMode, jboolean /*announce*/,
                                                    jboolean /*enableDHT*/,  jboolean /*enableLSD*/,
                                                    jboolean /*enableUTP*/,  jboolean /*enableTrackers*/,
                                                    jboolean /*enablePEX*/)
{
    const char* tf = env->GetStringUTFChars(jTorrentFile, nullptr);
    const char* sp = env->GetStringUTFChars(jSavePath  , nullptr);
    std::string torrentPath(tf), savePath(sp);
    env->ReleaseStringUTFChars(jTorrentFile, tf);
    env->ReleaseStringUTFChars(jSavePath   , sp);

    try {
        std::ifstream in(torrentPath, std::ios::binary);
        if (!in){ LOGE("cannot open %s", torrentPath.c_str()); return JNI_FALSE; }
        std::vector<char> buf{ std::istreambuf_iterator<char>(in), {} };
        error_code ec;
        bdecode_node node = bdecode(buf, ec);
        if (ec){ LOGE("bdecode: %s", ec.message().c_str()); return JNI_FALSE; }
        auto ti = std::make_shared<torrent_info>(node, ec);
        if (ec){ LOGE("torrent_info: %s", ec.message().c_str()); return JNI_FALSE; }
        add_torrent_params p;
        p.ti = ti;
        p.save_path = savePath;
        if (seedMode) p.flags |= torrent_flags::seed_mode;
        get_session().async_add_torrent(std::move(p));
        return JNI_TRUE;
    } catch (std::exception const& e) { LOGE("addTorrent ex: %s", e.what()); }
    return JNI_FALSE;
}

// createTorrent ------------------------------------------------------------
static void set_piece_hashes_manual(create_torrent& ct, const fs::path& file)
{
    const int piece = ct.piece_length();
    std::ifstream in(file, std::ios::binary);
    std::vector<char> buf(piece);
    for (int i=0; i < ct.num_pieces(); ++i) {
        in.read(buf.data(), piece);
        hasher h(buf.data(), static_cast<int>(in.gcount()));
        ct.set_hash(i, h.final());
    }
}

JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_createTorrent(JNIEnv* env, jobject,
                                                       jstring jFilePath, jstring jOutPath, jobjectArray jTrackers)
{
    const char* fp = env->GetStringUTFChars(jFilePath, nullptr);
    const char* op = env->GetStringUTFChars(jOutPath , nullptr);
    fs::path in(fp), out(op);
    env->ReleaseStringUTFChars(jFilePath, fp);
    env->ReleaseStringUTFChars(jOutPath , op);

    try {
        if (!fs::exists(in)) {
            LOGE("file missing %s", in.string().c_str());
            return JNI_FALSE;
        }
        file_storage fs;
        add_files(fs, in.string());
        create_torrent ct(fs);
        if (jTrackers) {
            jsize n = env->GetArrayLength(jTrackers);
            for (jsize i = 0; i < n; ++i) {
                auto jt = (jstring)env->GetObjectArrayElement(jTrackers, i);
                const char* s = env->GetStringUTFChars(jt, nullptr);
                ct.add_tracker(s);
                env->ReleaseStringUTFChars(jt, s);
                env->DeleteLocalRef(jt);
            }
        }
        set_piece_hashes_manual(ct, in);
        entry e = ct.generate();
        std::vector<char> data;
        bencode(std::back_inserter(data), e);
        std::ofstream(out, std::ios::binary).write(data.data(), data.size());
        return JNI_TRUE;
    } catch (std::exception const& e) {
        LOGE("createTorrent ex: %s", e.what());
    }
    return JNI_FALSE;
}

// getTorrentStats ----------------------------------------------------------
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getTorrentStats(JNIEnv* env, jobject)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_ses) return env->NewStringUTF("[]");
    std::ostringstream o;
    o << '[';
    auto v = g_ses->get_torrents();
    for (size_t i = 0; i < v.size(); ++i) {
        auto st = v[i].status();
        o << '{'
          << "\"info_hash\":\"" << to_hex_str(v[i].info_hash()) << "\","
          << "\"name\":\"" << st.name << "\","
          << "\"state\":" << int(st.state) << ","
          << "\"peers\":" << st.num_peers << ","
          << "\"upload_rate\":" << st.upload_payload_rate << ","
          << "\"download_rate\":" << st.download_payload_rate
          << '}';
        if (i + 1 < v.size()) o << ',';
    }
    o << ']';
    return env->NewStringUTF(o.str().c_str());
}

// getAllTorrents -----------------------------------------------------------
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getAllTorrents(JNIEnv* env, jobject)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_ses) return env->NewStringUTF("[]");
    std::ostringstream o;
    o << '[';
    auto v = g_ses->get_torrents();
    for (size_t i = 0; i < v.size(); ++i) {
        auto st = v[i].status();
        o << '{'
          << "\"info_hash\":\"" << to_hex_str(v[i].info_hash()) << "\","
          << "\"name\":\"" << st.name << "\","
          << "\"state\":" << int(st.state)
          << '}';
        if (i + 1 < v.size()) o << ',';
    }
    o << ']';
    return env->NewStringUTF(o.str().c_str());
}

// getInfoHash --------------------------------------------------------------
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getInfoHash(JNIEnv* env, jobject, jstring jPath)
{
    const char* p = env->GetStringUTFChars(jPath,nullptr);
    std::string hash = info_hash_from_torrent(p);
    env->ReleaseStringUTFChars(jPath,p);
    return env->NewStringUTF(hash.c_str());
}

// removeTorrentByInfoHash --------------------------------------------------
JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_removeTorrentByInfoHash(JNIEnv* env, jobject, jstring jHash)
{
    const char* h = env->GetStringUTFChars(jHash,nullptr);
    sha1_hash ih;
    try {
        ih = hex_to_sha1(h);
    } catch(...) {
        env->ReleaseStringUTFChars(jHash,h);
        return JNI_FALSE;
    }
    env->ReleaseStringUTFChars(jHash,h);
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_ses) return JNI_FALSE;
    auto hdl = g_ses->find_torrent(ih);
    if (!hdl.is_valid()) return JNI_FALSE;
    g_ses->remove_torrent(hdl);
    return JNI_TRUE;
}

// getTorrentSavePath -------------------------------------------------------
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getTorrentSavePath(JNIEnv* env, jobject, jstring jHash)
{
    const char* h = env->GetStringUTFChars(jHash,nullptr);
    sha1_hash ih;
    try {
        ih = hex_to_sha1(h);
    } catch(...) {
        env->ReleaseStringUTFChars(jHash,h);
        return nullptr;
    }
    env->ReleaseStringUTFChars(jHash,h);
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_ses) return nullptr;
    auto hdl = g_ses->find_torrent(ih);
    if (!hdl.is_valid()) return nullptr;
    return env->NewStringUTF(hdl.status().save_path.c_str());
}

// cleanupSession -----------------------------------------------------------
JNIEXPORT void JNICALL
Java_com_example_audyn_LibtorrentWrapper_cleanupSession(JNIEnv*, jobject)
{
std::lock_guard<std::mutex> lock(g_mtx);
g_ses.reset();
LOGI("[Native] session destroyed");
}

// dhtPutEncrypted ----------------------------------------------------------
// Updated to use correct bdecode overload and JNI signature

JNIEXPORT jboolean JNICALL
        Java_com_example_audyn_LibtorrentWrapper_dhtPutEncrypted
        (JNIEnv* env, jobject /*thiz*/, jstring jKey, jbyteArray jPayload)
{
// 1. pull out parameters
const jsize len = env->GetArrayLength(jPayload);
std::vector<char> buf(len);
env->GetByteArrayRegion(jPayload, 0, len, reinterpret_cast<jbyte*>(buf.data()));

// 2. decode – use the two‑arg overload that returns an entry
lt::entry e = lt::bdecode(buf.data(), buf.data() + len);

// 3. drop it into the local DHT
try {
get_session().dht_put_item(std::move(e));   // one‑arg overload
return JNI_TRUE;
} catch (...) {
return JNI_FALSE;
}
}

} // extern "C"
