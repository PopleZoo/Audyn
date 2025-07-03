#include <jni.h>
#include <string>
#include <iostream>
#include <fstream>
#include <memory>
#include <mutex>
#include <vector>
#include <sstream>
#include <cstdlib> // for getenv

#include <android/log.h>

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/hasher.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/entry.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/hex.hpp> // for from_hex

#if __has_include(<filesystem>)
#include <filesystem>
namespace fs = std::filesystem;
#else
#include <experimental/filesystem>
namespace fs = std::experimental::filesystem;
#endif

#define LOG_TAG "LibtorrentWrapper"
#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__))

static std::unique_ptr<lt::session> global_session;
static std::mutex session_mutex;

// === Helpers ===

lt::sha1_hash hex_to_sha1(const std::string& hex) {
    if (hex.size() != 40) throw std::invalid_argument("Invalid hex length for SHA1");
    lt::sha1_hash hash;
    lt::error_code ec;
    // Use c_str and length
    bool ok = lt::from_hex(hex.c_str(), static_cast<int>(hex.size()), hash.data());
    if (!ok) {
        throw std::runtime_error("Failed to parse hex to sha1_hash");
    }
    if (ec) {
        throw std::runtime_error("Failed to parse hex to sha1_hash: " + ec.message());
    }
    return hash;
}


std::string to_hex(const std::string& input) {
    static const char* hex_chars = "0123456789abcdef";
    std::string output;
    output.reserve(input.size() * 2);
    for (unsigned char c : input) {
        output.push_back(hex_chars[(c >> 4) & 0xF]);
        output.push_back(hex_chars[c & 0xF]);
    }
    return output;
}

std::string get_info_hash(const std::string& torrent_path) {
    lt::error_code ec;
    std::ifstream in(torrent_path, std::ios::binary);
    if (!in) {
        LOGE("[Native] Failed to open torrent file: %s", torrent_path.c_str());
        return "";
    }

    std::vector<char> buf((std::istreambuf_iterator<char>(in)), {});
    lt::bdecode_node node = lt::bdecode(buf, ec);
    if (ec) {
        LOGE("[Native] Failed to bdecode: %s", ec.message().c_str());
        return "";
    }

    auto ti = std::make_shared<lt::torrent_info>(node, ec);
    if (ec) {
        LOGE("[Native] Failed to create torrent_info: %s", ec.message().c_str());
        return "";
    }

    // info_hash() returns lt::sha1_hash, convert to hex string
    return to_hex(ti->info_hash().to_string());
}

// === Session Setup ===

lt::session& get_session() {
    std::lock_guard<std::mutex> lock(session_mutex);

    if (!global_session) {
        lt::settings_pack pack;

        // Enable full alert logging for diagnostics
        pack.set_int(lt::settings_pack::alert_mask, lt::alert::all_categories);

        // Enable only uTP (disable TCP)
        pack.set_bool(lt::settings_pack::enable_outgoing_utp, true);
        pack.set_bool(lt::settings_pack::enable_incoming_utp, true);
        pack.set_bool(lt::settings_pack::enable_outgoing_tcp, false);
        pack.set_bool(lt::settings_pack::enable_incoming_tcp, false);

        // Disable all external network discovery/mapping
        pack.set_bool(lt::settings_pack::enable_dht, false);
        pack.set_bool(lt::settings_pack::enable_lsd, false);
        pack.set_bool(lt::settings_pack::enable_upnp, false);
        pack.set_bool(lt::settings_pack::enable_natpmp, false);

        // Get port from environment variable or default to 6881
        int port = 6881;
        if (const char* port_env = std::getenv("LIBTORRENT_LISTEN_PORT")) {
            try {
                port = std::stoi(port_env);
            } catch (...) {
                LOGE("[Native] Invalid LIBTORRENT_LISTEN_PORT value. Falling back to 6881.");
            }
        }

        // Bind to all interfaces
        std::string listen_if = "0.0.0.0:" + std::to_string(port);
        pack.set_str(lt::settings_pack::listen_interfaces, listen_if);
        pack.set_int(lt::settings_pack::max_retry_port_bind, 10);

        global_session = std::make_unique<lt::session>(pack);
        LOGI("[Native] Libtorrent session initialized (uTP only) on %s", listen_if.c_str());
    }

    return *global_session;
}

// === JNI Methods ===

extern "C" {

JNIEXPORT void JNICALL
Java_com_example_audyn_LibtorrentWrapper_cleanupSession(JNIEnv*, jobject) {
std::lock_guard<std::mutex> lock(session_mutex);
if (global_session) {
auto handles = global_session->get_torrents();
for (auto& h : handles) {
if (h.is_valid()) {
global_session->remove_torrent(h, lt::session::delete_files);
}
}
global_session->pause();
global_session.reset();
LOGI("[Native] libtorrent session cleaned and destroyed");
}
}

JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getVersion(JNIEnv* env, jobject) {
    std::string version = "libtorrent ";
    version += LIBTORRENT_VERSION;
    return env->NewStringUTF(version.c_str());
}

JNIEXPORT jboolean JNICALL
        Java_com_example_audyn_LibtorrentWrapper_addTorrent(JNIEnv* env, jobject,
                                                            jstring torrentFilePath,
jstring savePath,
        jboolean seedMode,
jboolean announce,
        jboolean enableDHT,
jboolean enableLSD,
        jboolean enableUTP,
jboolean enableTrackers) {
const char* nativeTorrentPath = env->GetStringUTFChars(torrentFilePath, nullptr);
const char* nativeSavePath = env->GetStringUTFChars(savePath, nullptr);

std::string torrentFile(nativeTorrentPath);
std::string saveDir(nativeSavePath);

env->ReleaseStringUTFChars(torrentFilePath, nativeTorrentPath);
env->ReleaseStringUTFChars(savePath, nativeSavePath);

try {
std::ifstream in(torrentFile, std::ios::binary);
if (!in) {
LOGE("[Native] addTorrent: failed to open file %s", torrentFile.c_str());
return JNI_FALSE;
}

std::vector<char> buf((std::istreambuf_iterator<char>(in)), {});
lt::error_code ec;
lt::bdecode_node node = lt::bdecode(buf, ec);
if (ec) {
LOGE("[Native] addTorrent: bdecode failed: %s", ec.message().c_str());
return JNI_FALSE;
}

auto ti = std::make_shared<lt::torrent_info>(node, ec);
if (ec) {
LOGE("[Native] addTorrent: create torrent_info failed: %s", ec.message().c_str());
return JNI_FALSE;
}

lt::add_torrent_params params;
params.ti = ti;
params.save_path = saveDir;

// Deprecated flag_seed_mode removed
// If you want seed mode, do not set flag_seed_mode; instead, you can add torrent with flags 0 or adjust as per your libtorrent version

get_session().async_add_torrent(std::move(params));
return JNI_TRUE;
} catch (const std::exception& ex) {
LOGE("[Native] addTorrent exception: %s", ex.what());
return JNI_FALSE;
} catch (...) {
LOGE("[Native] addTorrent unknown exception");
return JNI_FALSE;
}
}

void set_piece_hashes_fallback(lt::create_torrent& ct, const std::string& content_path) {
    int piece_len = ct.piece_length();
    int num_pieces = ct.num_pieces();
    if (num_pieces <= 0) throw std::runtime_error("Invalid number of pieces");

    std::ifstream file(content_path, std::ios::binary);
    if (!file) throw std::runtime_error("Cannot open file for hashing");

    std::vector<char> buffer(piece_len);
    for (int i = 0; i < num_pieces; ++i) {
        file.read(buffer.data(), piece_len);
        std::streamsize read = file.gcount();
        lt::hasher h(buffer.data(), read);
        ct.set_hash(i, h.final());
    }
}

JNIEXPORT jboolean JNICALL
        Java_com_example_audyn_LibtorrentWrapper_createTorrent(JNIEnv* env, jobject,
                                                               jstring filePath, jstring outputPath, jobjectArray trackers) {
const char* inputPath = env->GetStringUTFChars(filePath, nullptr);
const char* outPath = env->GetStringUTFChars(outputPath, nullptr);

std::vector<std::string> trackerList;
if (trackers) {
jsize len = env->GetArrayLength(trackers);
for (jsize i = 0; i < len; ++i) {
jstring tracker = (jstring) env->GetObjectArrayElement(trackers, i);
const char* str = env->GetStringUTFChars(tracker, nullptr);
trackerList.emplace_back(str);
env->ReleaseStringUTFChars(tracker, str);
env->DeleteLocalRef(tracker);
}
}

try {
fs::path input(inputPath);
fs::path output(outPath);
if (!fs::exists(input)) {
LOGE("[Native] createTorrent: input path does not exist: %s", input.string().c_str());
env->ReleaseStringUTFChars(filePath, inputPath);
env->ReleaseStringUTFChars(outputPath, outPath);
return JNI_FALSE;
}

lt::file_storage fs_storage;
lt::add_files(fs_storage, input.string());
lt::create_torrent ct(fs_storage);

for (const auto& tracker : trackerList)
ct.add_tracker(tracker);

set_piece_hashes_fallback(ct, input.string());

ct.set_creator("audyn");
ct.set_comment("Generated by Audyn");

lt::entry e = ct.generate();
std::vector<char> torrentData;
lt::bencode(std::back_inserter(torrentData), e);

std::ofstream outFile(output, std::ios::binary);
outFile.write(torrentData.data(), torrentData.size());
outFile.close();

env->ReleaseStringUTFChars(filePath, inputPath);
env->ReleaseStringUTFChars(outputPath, outPath);
return JNI_TRUE;
} catch (const std::exception& ex) {
LOGE("[Native] createTorrent exception: %s", ex.what());
} catch (...) {
LOGE("[Native] createTorrent unknown exception");
}

env->ReleaseStringUTFChars(filePath, inputPath);
env->ReleaseStringUTFChars(outputPath, outPath);
return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_example_audyn_LibtorrentWrapper_getTorrentStats(JNIEnv* env, jobject) {
    std::lock_guard<std::mutex> lock(session_mutex);
    if (!global_session) return env->NewStringUTF("[]");

    std::ostringstream json;
    json << "[";
    auto handles = global_session->get_torrents();

    for (size_t i = 0; i < handles.size(); ++i) {
        lt::torrent_status st = handles[i].status();
        std::string infoHashHex = to_hex(handles[i].info_hash().to_string());

        json << "{";
        json << "\"info_hash\":\"" << infoHashHex << "\",";
        json << "\"name\":\"" << (st.name.empty() ? "Unknown" : st.name) << "\",";
        json << "\"state\":" << static_cast<int>(st.state) << ",";
        json << "\"peers\":" << st.num_peers << ",";
        json << "\"upload_rate\":" << st.upload_payload_rate << ",";
        json << "\"download_rate\":" << st.download_payload_rate;
        json << "}";
        if (i < handles.size() - 1) json << ",";
    }

    json << "]";
    return env->NewStringUTF(json.str().c_str());
}

JNIEXPORT jstring JNICALL
        Java_com_example_audyn_LibtorrentWrapper_getInfoHash(JNIEnv* env, jobject, jstring filePath) {
const char* nativePath = env->GetStringUTFChars(filePath, nullptr);
std::string hash = get_info_hash(nativePath);
env->ReleaseStringUTFChars(filePath, nativePath);
return env->NewStringUTF(hash.c_str());
}

JNIEXPORT jstring JNICALL
        Java_com_example_audyn_LibtorrentWrapper_getSwarmInfo(JNIEnv* env, jobject, jstring infoHash) {
const char* nativeHash = env->GetStringUTFChars(infoHash, nullptr);
std::string hash(nativeHash);
env->ReleaseStringUTFChars(infoHash, nativeHash);

std::lock_guard<std::mutex> lock(session_mutex);
if (!global_session) return env->NewStringUTF("{}");

for (const auto& handle : global_session->get_torrents()) {
if (to_hex(handle.info_hash().to_string()) == hash) {
lt::torrent_status st = handle.status();
std::ostringstream json;
json << "{";
json << "\"name\":\"" << st.name << "\",";
json << "\"state\":" << static_cast<int>(st.state) << ",";
json << "\"peers\":" << st.num_peers << ",";
json << "\"upload_rate\":" << st.upload_payload_rate << ",";
json << "\"download_rate\":" << st.download_payload_rate;
json << "}";
return env->NewStringUTF(json.str().c_str());
}
}

return env->NewStringUTF("{}");
}

JNIEXPORT jboolean JNICALL
        Java_com_example_audyn_LibtorrentWrapper_removeTorrentByInfoHash(JNIEnv* env, jobject, jstring jInfoHash) {
std::lock_guard<std::mutex> lock(session_mutex);
if (!global_session) {
LOGE("[Native] removeTorrentByInfoHash called but session is null");
return JNI_FALSE;
}

const char* cHash = env->GetStringUTFChars(jInfoHash, nullptr);
std::string infoHash(cHash);
env->ReleaseStringUTFChars(jInfoHash, cHash);

try {
lt::sha1_hash hash = hex_to_sha1(infoHash);
lt::torrent_handle handle = global_session->find_torrent(hash);
if (!handle.is_valid()) {
LOGE("[Native] removeTorrentByInfoHash: torrent handle invalid for hash %s", infoHash.c_str());
return JNI_FALSE;
}
global_session->remove_torrent(handle);
LOGI("[Native] Torrent removed: %s", infoHash.c_str());
return JNI_TRUE;
} catch (const std::exception& ex) {
LOGE("[Native] removeTorrentByInfoHash exception: %s", ex.what());
return JNI_FALSE;
} catch (...) {
LOGE("[Native] removeTorrentByInfoHash unknown exception");
return JNI_FALSE;
}
}

JNIEXPORT jstring JNICALL
        Java_com_example_audyn_LibtorrentWrapper_getTorrentSavePath(JNIEnv* env, jobject, jstring jInfoHash) {
const char* infoHashCStr = env->GetStringUTFChars(jInfoHash, nullptr);
std::string infoHashStr(infoHashCStr);
env->ReleaseStringUTFChars(jInfoHash, infoHashCStr);

try {
lt::sha1_hash hash = hex_to_sha1(infoHashStr);
std::lock_guard<std::mutex> lock(session_mutex);
if (!global_session) return nullptr;

lt::torrent_handle handle = global_session->find_torrent(hash);
if (handle.is_valid()) {
lt::torrent_status st = handle.status();
std::string savePath = st.save_path;
return env->NewStringUTF(savePath.c_str());
}
} catch (const std::exception& e) {
LOGE("[Native] getTorrentSavePath exception: %s", e.what());
} catch (...) {
LOGE("[Native] getTorrentSavePath unknown exception");
}
return nullptr;
}


} // extern "C"
