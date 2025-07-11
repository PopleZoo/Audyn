// LibtorrentWrapper.cpp  –  C++17, single TU
// -------------------------------------------------------------
#include <jni.h>
#include <android/log.h>
#include <fstream>
#include <string>
#include <mutex>
#include <vector>
#include <thread>
#include <chrono>
#include <sstream>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/file_storage.hpp>
#include <sys/stat.h>
#include <future>
#include <jni.h>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/sha1_hash.hpp>
#include <libtorrent/hex.hpp>


#define  LOG_TAG  "LibtorrentWrapper"
#define  LOGI(...)  ((void)__android_log_print(ANDROID_LOG_INFO ,LOG_TAG,__VA_ARGS__))
#define  LOGE(...)  ((void)__android_log_print(ANDROID_LOG_ERROR,LOG_TAG,__VA_ARGS__))

using namespace lt;          // libtorrent namespace
using lt::torrent_flags::seed_mode;
using lt::torrent_flags::paused;
using lt::torrent_flags::disable_dht;
using lt::torrent_flags::disable_lsd;
using lt::torrent_flags::disable_pex;

// ─────────────────────────  globals  ──────────────────────────
static std::unique_ptr<session> g_ses;
static std::mutex               g_mtx;

// ───────────────────────── helpers ────────────────────────────
static session& get_session()
{
    std::lock_guard<std::mutex> lk(g_mtx);
    if (g_ses) return *g_ses;

    settings_pack sp;
    sp.set_int(settings_pack::alert_mask,
               alert::error_notification |
               alert::status_notification |
               alert::dht_notification);

    sp.set_bool(settings_pack::enable_outgoing_tcp ,true);
    sp.set_bool(settings_pack::enable_incoming_tcp ,true);
    sp.set_bool(settings_pack::enable_outgoing_utp ,true);
    sp.set_bool(settings_pack::enable_incoming_utp ,true);
    sp.set_bool(settings_pack::enable_dht          ,true);
    sp.set_bool(settings_pack::enable_lsd          ,true);
    sp.set_bool(settings_pack::enable_upnp         ,true);
    sp.set_bool(settings_pack::enable_natpmp       ,true);
    sp.set_str (settings_pack::listen_interfaces, "0.0.0.0:6881");

    g_ses = std::make_unique<session>(sp);

    // (Deprecated, but harmless)
    g_ses->add_dht_router({"67.215.246.10", 6881});
    g_ses->add_dht_router({"82.221.103.244", 6881});

    LOGI("libtorrent %s session started", LIBTORRENT_VERSION);

    // background alert pump
    std::thread([]{
        while (true) {
            std::vector<alert*> alerts;
            {
                std::lock_guard<std::mutex> lk(g_mtx);
                if (!g_ses) break;
                g_ses->pop_alerts(&alerts);
            }
            for (auto* a : alerts) {
                if (auto* b = alert_cast<dht_error_alert>(a))
                    LOGE("[DHT] %s", b->message().c_str());
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(250));
        }
    }).detach();

    return *g_ses;
}

std::string escape_json_string(const std::string& s) {
    std::ostringstream o;
    for (auto c : s) {
        switch (c) {
            case '"': o << "\\\""; break;
            case '\\': o << "\\\\"; break;
            case '\b': o << "\\b"; break;
            case '\f': o << "\\f"; break;
            case '\n': o << "\\n"; break;
            case '\r': o << "\\r"; break;
            case '\t': o << "\\t"; break;
            default:
                if ('\x00' <= c && c <= '\x1f') {
                    o << "\\u" << std::hex << (int)c;
                } else {
                    o << c;
                }
        }
    }
    return o.str();
}

// Recursive conversion from libtorrent::entry to JSON string
std::string entry_to_json(const lt::entry& e) {
    using namespace lt;

    switch (e.type()) {
        case entry::int_t:
            return std::to_string(e.integer());
        case entry::string_t:
            return "\"" + escape_json_string(e.string()) + "\"";
        case entry::list_t: {
            std::string res = "[";
            bool first = true;
            for (auto& item : e.list()) {
                if (!first) res += ",";
                res += entry_to_json(item);
                first = false;
            }
            res += "]";
            return res;
        }
        case entry::dictionary_t: {
            std::string res = "{";
            bool first = true;
            for (auto& pair : e.dict()) {
                if (!first) res += ",";
                res += "\"" + escape_json_string(pair.first) + "\":" + entry_to_json(pair.second);
                first = false;
            }
            res += "}";
            return res;
        }
        default:
            return "\"\""; // fallback empty string for unknown types
    }
}

// ────────────────────────  JNI exports  ───────────────────────
extern "C" {


extern "C" JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getAllTorrents(JNIEnv* env, jobject) {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (!g_ses) return env->NewStringUTF("[]");

    lt::entry::list_type lst;

    for (const auto& th : g_ses->get_torrents()) {
        if (!th.is_valid()) continue;
        const lt::torrent_status st = th.status();

        lt::entry::dictionary_type d;
        d["name"]           = st.name;
        d["state"]          = static_cast<int>(st.state);
        d["progress"]       = st.progress;
        d["num_peers"]      = static_cast<int>(st.num_peers);
        d["download_rate"]  = st.download_rate;
        d["upload_rate"]    = st.upload_rate;
        d["save_path"]      = th.save_path();

        lst.push_back(std::move(d));
    }

    lt::entry allTorrentsEntry(lst);
    std::string jsonStr = entry_to_json(allTorrentsEntry);
    return env->NewStringUTF(jsonStr.c_str());
}

// -----------------------------------------------------------------
// getTorrentStats()  →  JSON (bencoded list of dictionaries)
// -----------------------------------------------------------------
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getTorrentStats(JNIEnv* env, jobject) {
    std::lock_guard<std::mutex> lk(g_mtx);
    if (!g_ses) return env->NewStringUTF("[]");

    lt::entry::list_type lst;

    for (const auto& th : g_ses->get_torrents()) {
        if (!th.is_valid()) continue;
        const lt::torrent_status st = th.status();

        lt::entry::dictionary_type d;
        d["name"]           = st.name;
        d["state"]          = static_cast<int>(st.state);
        d["progress"]       = st.progress;
        d["num_peers"]      = static_cast<int>(st.num_peers);
        d["download_rate"]  = st.download_rate;
        d["upload_rate"]    = st.upload_rate;
        d["save_path"]      = th.save_path();

        lst.push_back(std::move(d));
    }

    lt::entry allTorrentsEntry(lst);
    std::string jsonStr = entry_to_json(allTorrentsEntry);
    return env->NewStringUTF(jsonStr.c_str());
}


// -----------------------------------------------------------------
// addTorrent(...)
// -----------------------------------------------------------------
JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_addTorrent(JNIEnv* env, jobject,
                                                    jstring jPath,
                                                    jstring jSave,
                                                    jboolean jSeed,
                                                    jboolean jAnnounce,
                                                    jboolean jEnableDHT,
                                                    jboolean jEnableLSD,
                                                    jboolean jEnableUTP,
                                                    jboolean jEnableTrackers,
                                                    jboolean jEnablePEX)
{
    if (!jPath || !jSave) return JNI_FALSE;

    const char* path  = env->GetStringUTFChars(jPath , nullptr);
    const char* spath = env->GetStringUTFChars(jSave , nullptr);

    bool ok = false;
    try {
        auto& ses = get_session();

        error_code ec;
        auto ti = std::make_shared<torrent_info>(std::string(path), ec);
        if (ec) throw std::runtime_error(ec.message());

        add_torrent_params p;
        p.ti        = ti;
        p.save_path = spath;
        p.flags     = {};

        if (jSeed)              p.flags |= seed_mode;
        if (!jAnnounce)         p.flags |= paused;
        if (!jEnableDHT)        p.flags |= disable_dht;
        if (!jEnableLSD)        p.flags |= disable_lsd;
        if (!jEnablePEX)        p.flags |= disable_pex;

        if (!jEnableTrackers)   p.trackers.clear();

        // Disable uTP globally if requested
        if (!jEnableUTP) {
            settings_pack s;
            s.set_bool(settings_pack::enable_outgoing_utp, false);
            s.set_bool(settings_pack::enable_incoming_utp, false);
            ses.apply_settings(s);
        }

        ses.async_add_torrent(std::move(p));
        ok = true;
    }
    catch (std::exception const& e) { LOGE("addTorrent: %s", e.what()); }

    env->ReleaseStringUTFChars(jPath , path );
    env->ReleaseStringUTFChars(jSave , spath);
    return ok ? JNI_TRUE : JNI_FALSE;
}


bool file_exists(const std::string& path) {
    struct ::stat buffer;  // <-- use ::stat to refer to system stat
    return (::stat(path.c_str(), &buffer) == 0);
}

JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_createTorrent(JNIEnv* env, jobject,
                                                       jstring jFilePath,
                                                       jstring jOutputPath,
                                                       jobjectArray jTrackers) {
    if (!jFilePath || !jOutputPath) return JNI_FALSE;

    const char* filePath = env->GetStringUTFChars(jFilePath, nullptr);
    const char* outputPath = env->GetStringUTFChars(jOutputPath, nullptr);

    std::string inputPathStr(filePath);
    std::string outputPathStr(outputPath);

    env->ReleaseStringUTFChars(jFilePath, filePath);
    env->ReleaseStringUTFChars(jOutputPath, outputPath);

    bool result = false;
    std::mutex mtx;
    std::condition_variable cv;
    bool done = false;

    std::thread worker([&]() {
        try {
            lt::file_storage fs;
            lt::add_files(fs, inputPathStr);

            lt::create_torrent t(fs);

            // Add trackers from jobjectArray jTrackers
            if (jTrackers != nullptr) {
                jsize trackerCount = env->GetArrayLength(jTrackers);
                for (jsize i = 0; i < trackerCount; ++i) {
                    jstring jTracker = (jstring)env->GetObjectArrayElement(jTrackers, i);
                    if (jTracker) {
                        const char* trackerStr = env->GetStringUTFChars(jTracker, nullptr);
                        if (trackerStr) {
                            t.add_tracker(trackerStr);
                            env->ReleaseStringUTFChars(jTracker, trackerStr);
                        }
                        env->DeleteLocalRef(jTracker);
                    }
                }
            }

            lt::error_code ec;

            auto progress_cb = [&](lt::piece_index_t piece) {
                LOGI("Hashing piece %d", piece);
                return false; // false = continue hashing, true = cancel
            };

            // Correct call: callback before error_code
            lt::set_piece_hashes(t, inputPathStr, progress_cb, ec);

            if (ec) {
                LOGE("set_piece_hashes failed: [%s] %s", ec.category().name(), ec.message().c_str());
                result = false;
            } else {
                lt::entry e = t.generate();
                std::vector<char> buffer;
                lt::bencode(std::back_inserter(buffer), e);

                std::ofstream outFile(outputPathStr, std::ios::binary | std::ios::trunc);
                if (!outFile.is_open()) {
                    LOGE("Failed to open output file: %s", outputPathStr.c_str());
                    result = false;
                } else {
                    outFile.write(buffer.data(), buffer.size());
                    outFile.close();
                    LOGI("Torrent successfully created at: %s", outputPathStr.c_str());
                    result = true;
                }
            }
        } catch (const std::exception& e) {
            LOGE("Exception during createTorrent: %s", e.what());
            result = false;
        }

        {
            std::lock_guard<std::mutex> lock(mtx);
            done = true;
        }
        cv.notify_one();
    });

    // Wait for thread to finish
    {
        std::unique_lock<std::mutex> lock(mtx);
        cv.wait(lock, [&] { return done; });
    }

    worker.join();

    return result ? JNI_TRUE : JNI_FALSE;
}


// -----------------------------------------------------------------
// removeTorrentByName(name)  → bool
// -----------------------------------------------------------------
JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_removeTorrentByName(JNIEnv* env, jobject,
                                                             jstring jName)
{
    if (!jName) return JNI_FALSE;
    const char* name = env->GetStringUTFChars(jName, nullptr);

    bool removed = false;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        if (!g_ses) goto done;

        for (auto const& th : g_ses->get_torrents()) {
            if (!th.is_valid()) continue;
            if (th.status().name == name) {
                g_ses->remove_torrent(th);
                removed = true;
                break;
            }
        }
    }
    done:
    env->ReleaseStringUTFChars(jName, name);
    return removed ? JNI_TRUE : JNI_FALSE;
}

// -----------------------------------------------------------------
// getTorrentSavePathByName(name)  → String?
// -----------------------------------------------------------------
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getTorrentSavePathByName(JNIEnv* env, jobject,
                                                                  jstring jName)
{
    if (!jName) return env->NewStringUTF("");
    const char* name = env->GetStringUTFChars(jName, nullptr);

    std::string path;
    {
        std::lock_guard<std::mutex> lk(g_mtx);
        if (g_ses) {
            for (auto const& th : g_ses->get_torrents()) {
                if (th.is_valid() && th.status().name == name) {
                    path = th.save_path();  // deprecated, but OK
                    break;
                }
            }
        }
    }

    env->ReleaseStringUTFChars(jName, name);
    return env->NewStringUTF(path.c_str());
}
// build an in‑memory torrent and return as jbyteArray
static jbyteArray make_torrent_bytes(JNIEnv* env, const std::string& filePath)
{
    lt::file_storage fs;
    lt::add_files(fs, filePath);
    if (fs.num_files() == 0) return nullptr;

    lt::create_torrent t(fs);
    std::string parent = filePath.substr(0, filePath.find_last_of('/'));

    lt::error_code ec;
    lt::set_piece_hashes(t, parent, [&](lt::piece_index_t) { return false; }, ec);
    if (ec) return nullptr;

    std::vector<char> buf;
    lt::bencode(std::back_inserter(buf), t.generate());

    jbyteArray arr = env->NewByteArray(static_cast<jsize>(buf.size()));
    env->SetByteArrayRegion(
            arr, 0, static_cast<jsize>(buf.size()),
            reinterpret_cast<const jbyte*>(buf.data())
    );
    return arr;
}

/* ─────────────────────────────  NEW JNI wrapper  ─────────────────────────── */

extern "C"
JNIEXPORT jbyteArray JNICALL
Java_com_example_audyn_LibtorrentWrapper_createTorrentBytes
        (JNIEnv* env, jobject /*thiz*/, jstring jSourcePath)
{
    if (!jSourcePath) return nullptr;

    const char* src = env->GetStringUTFChars(jSourcePath, nullptr);
    std::string path(src ? src : "");
    env->ReleaseStringUTFChars(jSourcePath, src);

    // Use the tested helper that already does the “parent‑dir” dance
    jbyteArray arr = make_torrent_bytes(env, path);

    if (arr == nullptr) {
        LOGE("createTorrentBytes: failed to generate torrent for \"%s\"", path.c_str());
    }
    return arr;        // null -> Dart will see “null bytes”
}



JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_addTorrentFromBytes
        (JNIEnv* env, jobject /*thiz*/,
         jbyteArray jBytes, jstring jSavePath,
         jboolean jSeed, jboolean jAnnounce,
         jboolean jEnableDHT, jboolean jEnableLSD, jboolean jEnableUTP,
         jboolean jEnableTrackers, jboolean jEnablePEX)
{
    if (!jBytes || !jSavePath) return JNI_FALSE;

    // grab inputs
    jsize len     = env->GetArrayLength(jBytes);
    jbyte* buffer = env->GetByteArrayElements(jBytes, nullptr);
    const char* save = env->GetStringUTFChars(jSavePath, nullptr);

    bool ok = false;
    try {
        auto& ses = get_session();

        lt::error_code ec;
        lt::bdecode_node root;
        lt::bdecode(reinterpret_cast<char const*>(buffer),
                    reinterpret_cast<char const*>(buffer) + len,
                    root, ec);
        if (ec) throw std::runtime_error(ec.message());

        auto ti = std::make_shared<lt::torrent_info>(root, ec);
        if (ec) throw std::runtime_error(ec.message());

        lt::add_torrent_params p;
        p.ti        = ti;
        p.save_path = save;
        if (jSeed)           p.flags |= seed_mode;
        if (!jAnnounce)      p.flags |= paused;
        if (!jEnableDHT)     p.flags |= disable_dht;
        if (!jEnableLSD)     p.flags |= disable_lsd;
        if (!jEnablePEX)     p.flags |= disable_pex;
        if (!jEnableTrackers) p.trackers.clear();

        if (!jEnableUTP) {
            lt::settings_pack sp;
            sp.set_bool(lt::settings_pack::enable_outgoing_utp, false);
            sp.set_bool(lt::settings_pack::enable_incoming_utp, false);
            ses.apply_settings(sp);
        }

        ses.async_add_torrent(std::move(p));
        ok = true;
    } catch (std::exception const& e) {
        LOGE("addTorrentFromBytes: %s", e.what());
    }

    // cleanup JNI refs
    env->ReleaseByteArrayElements(jBytes, buffer, JNI_ABORT);
    env->ReleaseStringUTFChars(jSavePath, save);
    return ok ? JNI_TRUE : JNI_FALSE;
}
extern libtorrent::session* g_session;

extern "C"
lt::sha1_hash hex_to_sha1(const std::string& hex) {
    lt::sha1_hash hash;
    for (int i = 0; i < 20; ++i) {
        std::string byteString = hex.substr(i * 2, 2);
        hash[i] = static_cast<unsigned char>(std::stoul(byteString, nullptr, 16));
    }
    return hash;
}

JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_isTorrentActive(JNIEnv *env, jobject thiz, jstring j_info_hash) {
    const char *info_hash_str = env->GetStringUTFChars(j_info_hash, nullptr);
    std::string hashStr(info_hash_str ? info_hash_str : "");
    env->ReleaseStringUTFChars(j_info_hash, info_hash_str);

    if (hashStr.length() != 40) {
        LOGE("Invalid infoHash length: %s", hashStr.c_str());
        return JNI_FALSE;
    }

    lt::sha1_hash hash = hex_to_sha1(hashStr);

    std::lock_guard<std::mutex> lk(g_mtx);
    if (!g_ses) return JNI_FALSE;

    auto handle = g_ses->find_torrent(hash);
    bool isActive = handle.is_valid() && !handle.status().paused;
    return isActive ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_startTorrentByHash(JNIEnv *env, jobject /*thiz*/, jstring j_info_hash) {
    const char *info_hash_str = env->GetStringUTFChars(j_info_hash, nullptr);
    std::string hashStr(info_hash_str ? info_hash_str : "");
    env->ReleaseStringUTFChars(j_info_hash, info_hash_str);

    if (hashStr.length() != 40) {
        LOGE("Invalid infoHash length: %s", hashStr.c_str());
        return JNI_FALSE;
    }

    lt::sha1_hash hash = hex_to_sha1(hashStr);

    std::lock_guard<std::mutex> lk(g_mtx);
    if (!g_ses) return JNI_FALSE;

    auto handle = g_ses->find_torrent(hash);
    if (!handle.is_valid()) {
        LOGE("startTorrentByHash: No valid torrent found for hash %s", hashStr.c_str());
        return JNI_FALSE;
    }

    if (handle.status().paused) {
        handle.resume();
        LOGI("Torrent resumed for hash: %s", hashStr.c_str());
    } else {
        LOGI("Torrent already running for hash: %s", hashStr.c_str());
    }

    return JNI_TRUE;
}
// JNI wrapper for getInfoHash
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getInfoHash(JNIEnv* env, jobject, jstring torrentPath) {
    const char* nativePath = env->GetStringUTFChars(torrentPath, nullptr);
    if (!nativePath) return env->NewStringUTF("");

    std::vector<char> buf;
    std::ifstream in(nativePath, std::ios_base::binary);
    if (!in) {
        env->ReleaseStringUTFChars(torrentPath, nativePath);
        return env->NewStringUTF("");
    }

    in.unsetf(std::ios_base::skipws);
    in.seekg(0, std::ios_base::end);
    std::streampos fileSize = in.tellg();
    in.seekg(0, std::ios_base::beg);
    buf.reserve(fileSize);
    buf.insert(buf.begin(),
               std::istream_iterator<char>(in),
               std::istream_iterator<char>());

    lt::error_code ec;
    lt::bdecode_node node;
    lt::bdecode(buf.data(), buf.data() + buf.size(), node, ec);
    if (ec) {
        env->ReleaseStringUTFChars(torrentPath, nativePath);
        return env->NewStringUTF("");
    }

    lt::torrent_info ti(node, ec);
    if (ec) {
        env->ReleaseStringUTFChars(torrentPath, nativePath);
        return env->NewStringUTF("");
    }

    std::string hash = ti.info_hashes().v1.to_string();
    env->ReleaseStringUTFChars(torrentPath, nativePath);
    return env->NewStringUTF(hash.c_str());
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getInfoHashFromBytes(
        JNIEnv *env,
        jobject /* this */,
        jbyteArray torrentBytes) {

    jsize length = env->GetArrayLength(torrentBytes);
    std::vector<char> buffer(length);
    env->GetByteArrayRegion(torrentBytes, 0, length, reinterpret_cast<jbyte *>(buffer.data()));

    try {
        lt::error_code ec;
        lt::bdecode_node node;
        lt::bdecode(buffer.data(), buffer.data() + buffer.size(), node, ec);

        if (ec) {
            std::string err = "Failed to bdecode: " + ec.message();
            return env->NewStringUTF(err.c_str());
        }

        // Create torrent_info from bdecoded node
        lt::torrent_info info(node, ec);

        if (ec) {
            std::string err = "Failed to parse torrent_info: " + ec.message();
            return env->NewStringUTF(err.c_str());
        }

        lt::sha1_hash hash = info.info_hashes().v1;  // For v1 torrents
        std::ostringstream oss;
        oss << hash;

        return env->NewStringUTF(oss.str().c_str());

    } catch (const std::exception &ex) {
        std::string err = "Exception: " + std::string(ex.what());
        return env->NewStringUTF(err.c_str());
    }
}
JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_stopTorrentByHash(JNIEnv *env, jobject /* this */, jstring infoHashJ) {
    const char *infoHashC = env->GetStringUTFChars(infoHashJ, nullptr);
    std::string infoHash(infoHashC);
    env->ReleaseStringUTFChars(infoHashJ, infoHashC);

    if (infoHash.length() != 40) {
        LOGE("stopTorrentByHash: invalid hash length: %s", infoHash.c_str());
        return JNI_FALSE;
    }

    try {
        lt::sha1_hash hash;
        lt::from_hex(infoHash.c_str(), infoHash.size(), hash.data());

        std::lock_guard<std::mutex> lk(g_mtx);
        if (!g_ses) return JNI_FALSE;

        auto handle = g_ses->find_torrent(hash);
        if (handle.is_valid()) {
            handle.pause();
            LOGI("Torrent paused for hash: %s", infoHash.c_str());
            return JNI_TRUE;
        }
    } catch (const std::exception& e) {
        LOGE("stopTorrentByHash exception: %s", e.what());
    } catch (...) {
        LOGE("stopTorrentByHash: unknown exception");
    }

    return JNI_FALSE;
}


} // extern "C"