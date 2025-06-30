#include <jni.h>
#include <string>
#include <iostream>
#include <fstream>
#include <memory>
#include <mutex>
#include <vector>
#include <sstream>

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

extern "C" {

// === Helpers ===
static const char* hex_chars = "0123456789abcdef";

lt::sha1_hash hex_to_sha1(const std::string& hex) {
    if (hex.size() != 40) throw std::invalid_argument("Invalid hex length");
    lt::sha1_hash hash;
    for (int i = 0; i < 20; ++i) {
        std::string byteStr = hex.substr(i * 2, 2);
        hash[i] = static_cast<unsigned char>(std::stoul(byteStr, nullptr, 16));
    }
    return hash;
}

std::string to_hex(const std::string& input) {
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

    return to_hex(ti->info_hash().to_string());
}

// === Session Setup ===
lt::session& get_session() {
    std::lock_guard<std::mutex> lock(session_mutex);
    if (!global_session) {
        lt::settings_pack pack;
        pack.set_int(lt::settings_pack::alert_mask, lt::alert::all_categories);
        pack.set_bool(lt::settings_pack::enable_dht, true);
        pack.set_bool(lt::settings_pack::enable_lsd, true);
        pack.set_bool(lt::settings_pack::enable_upnp, true);
        pack.set_bool(lt::settings_pack::enable_natpmp, true);
        pack.set_bool(lt::settings_pack::enable_outgoing_utp, true);
        pack.set_bool(lt::settings_pack::enable_incoming_utp, true);
        global_session = std::make_unique<lt::session>(pack);
        LOGI("[Native] libtorrent session initialized");
    }
    return *global_session;
}

// === JNI Methods ===

JNIEXPORT void JNICALL
Java_com_example_audyn_LibtorrentWrapper_cleanupSession(JNIEnv*, jobject) {
    std::lock_guard<std::mutex> lock(session_mutex);
    global_session.reset();
    LOGI("[Native] libtorrent session cleaned up");
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

    LOGI("[Native] Adding torrent file: %s", torrentFile.c_str());

    try {
        std::ifstream in(torrentFile, std::ios::binary);
        if (!in) return JNI_FALSE;

        std::vector<char> buf((std::istreambuf_iterator<char>(in)), {});
        lt::error_code ec;
        lt::bdecode_node node = lt::bdecode(buf, ec);
        if (ec) return JNI_FALSE;

        auto ti = std::make_shared<lt::torrent_info>(node, ec);
        if (ec) return JNI_FALSE;

        lt::add_torrent_params params;
        params.ti = ti;
        params.save_path = saveDir;
        if (seedMode) params.flags |= lt::add_torrent_params::flag_seed_mode;

        lt::settings_pack sp;
        sp.set_bool(lt::settings_pack::enable_dht, enableDHT);
        sp.set_bool(lt::settings_pack::enable_lsd, enableLSD);
        sp.set_bool(lt::settings_pack::enable_upnp, announce);
        sp.set_bool(lt::settings_pack::enable_natpmp, announce);
        sp.set_bool(lt::settings_pack::enable_outgoing_utp, enableUTP);
        sp.set_bool(lt::settings_pack::enable_incoming_utp, enableUTP);

        lt::session& ses = get_session();
        ses.apply_settings(sp);
        ses.add_torrent(std::move(params), ec);

        return ec ? JNI_FALSE : JNI_TRUE;
    } catch (...) {
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

        if (!fs::exists(input)) return JNI_FALSE;

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
    } catch (...) {
        env->ReleaseStringUTFChars(filePath, inputPath);
        env->ReleaseStringUTFChars(outputPath, outPath);
        return JNI_FALSE;
    }
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
        json << "{";
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
        lt::torrent_status st = handle.status();
        if (to_hex(handle.info_hash().to_string()) == hash) {
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
    if (!global_session) return JNI_FALSE;

    const char* cHash = env->GetStringUTFChars(jInfoHash, nullptr);
    std::string infoHash(cHash);
    env->ReleaseStringUTFChars(jInfoHash, cHash);

    try {
        lt::sha1_hash hash = hex_to_sha1(infoHash);
        lt::torrent_handle handle = global_session->find_torrent(hash);
        if (!handle.is_valid()) return JNI_FALSE;
        global_session->remove_torrent(handle);
        return JNI_TRUE;
    } catch (...) {
        return JNI_FALSE;
    }
}

} // extern "C"
