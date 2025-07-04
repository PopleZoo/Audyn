// LibtorrentWrapper.cpp — self‑contained C++17 source file that builds with clang++/NDK
// -----------------------------------------------------------------------------

#include <jni.h>
#include <android/log.h>

#include <string>
#include <fstream>
#include <sstream>
#include <memory>
#include <mutex>
#include <vector>
#include <thread>
#include <chrono>
#include <iomanip>  // for setw and setfill

#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/bdecode.hpp>
#include <libtorrent/bencode.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/kademlia/item.hpp>

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

static std::unique_ptr<session> g_ses;
static std::mutex g_mtx;

static std::string to_hex(const sha1_hash &h) { return aux::to_hex(h); }

static sha1_hash hex_to_sha1(const std::string &hex)
{
    sha1_hash out;
    if (!aux::from_hex(hex, out.data())) throw std::runtime_error("bad hex");
    return out;
}

static session &get_session()
{
    std::lock_guard<std::mutex> lk(g_mtx);
    if (g_ses) return *g_ses;

    settings_pack sp;
    sp.set_int(settings_pack::alert_mask, alert::error_notification | alert::status_notification | alert::dht_notification);
    sp.set_bool(settings_pack::enable_outgoing_tcp , true);
    sp.set_bool(settings_pack::enable_incoming_tcp , true);
    sp.set_bool(settings_pack::enable_outgoing_utp , true);
    sp.set_bool(settings_pack::enable_incoming_utp , true);
    sp.set_bool(settings_pack::enable_dht  , true);
    sp.set_bool(settings_pack::enable_lsd  , true);
    sp.set_bool(settings_pack::enable_upnp , true);
    sp.set_bool(settings_pack::enable_natpmp, true);
    sp.set_str(settings_pack::listen_interfaces, "0.0.0.0:6881");

    g_ses = std::make_unique<session>(sp);

    auto add_router = [](const char *host, int port){
        g_ses->add_dht_router(std::make_pair(std::string(host), port));
        LOGI("Added DHT router: %s:%d", host, port);
    };
    add_router("67.215.246.10", 6881);
    add_router("82.221.103.244", 6881);

    LOGI("[Native] libtorrent %s session started", LIBTORRENT_VERSION);

    std::thread([]{
        while(true) {
            std::vector<alert*> alerts;
            {
                std::lock_guard<std::mutex> lk(g_mtx);
                if (!g_ses) break;
                g_ses->pop_alerts(&alerts);
            }
            for (alert *a : alerts) {
                if (auto *e = alert_cast<dht_bootstrap_alert>(a))
                    LOGI("[DHT] bootstrap %s", e->message().c_str());
                else if (auto *e2 = alert_cast<dht_error_alert>(a))
                    LOGE("[DHT] error %s", e2->message().c_str());
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(250));
        }
    }).detach();

    return *g_ses;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_audyn_LibtorrentWrapper_removeTorrentByName(JNIEnv* env, jobject, jstring jTorrentName) {
    if (jTorrentName == nullptr) return JNI_FALSE;

    const char* torrentNameCStr = env->GetStringUTFChars(jTorrentName, nullptr);
    if (!torrentNameCStr) return JNI_FALSE;

    std::string torrentName(torrentNameCStr);
    env->ReleaseStringUTFChars(jTorrentName, torrentNameCStr);

    std::lock_guard<std::mutex> lk(g_mtx);
    if (!g_ses) {
        LOGE("Session not started");
        return JNI_FALSE;
    }

    for (auto const& th : g_ses->get_torrents()) {
        if (!th.is_valid()) continue;
        lt::torrent_status status = th.status();
        if (status.name == torrentName) {
            g_ses->remove_torrent(th, session::delete_files);
            LOGI("Removed torrent: %s", torrentName.c_str());
            return JNI_TRUE;
        }
    }

    LOGE("Torrent with name %s not found", torrentName.c_str());
    return JNI_FALSE;
}
