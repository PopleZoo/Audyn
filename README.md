# 🎵 Audyn

**Audyn** is a decentralized, peer-to-peer music app built with Flutter. It empowers users to share and stream music using a private torrent swarm, built for speed, privacy, and long-term resilience — without relying on traditional servers.

---

## ✨ Features

- 🎶 **Local Music Playback** – Play your own files with seamless organization using MusicBrainz metadata.  
- 🌐 **Private Torrent Swarm** – Share music between users through encrypted, app-specific torrenting.  
- 🧠 **Smart Metadata Matching** – Automatically tags tracks via MusicBrainz for better library control.  
- 📊 **Play Count Tracking** – Build toward personalized playlists based on actual listening habits.  
- 🛡 **Decentralized by Design** – No central server. No hosted content. Full user control.  
- 🔒 **Content Flagging** – Tracks are flagged by source (local upload vs public provider) for visibility.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install)  
- Dart 3.x  
- Android Studio or compatible IDE  

### Clone and Run
```bash
git clone https://github.com/your-username/audyn.git
cd audyn
flutter pub get
flutter run
```
📦 If your project uses large assets or .torrent metadata, be sure to run git lfs install if you're using Git LFS.
---
### 📁 Project Structure
```bash
lib/
├── models/         # MusicTrack, Playlist, Torrent metadata
├── services/       # Playback, Metadata, Torrent Engine
├── ui/             # Screens, Widgets, Player
├── utils/          # Helpers and constants
```
---
### ⚠️ Legal Disclaimer

Audyn does not host, index, or distribute copyrighted content.
All files shared via Audyn are user-contributed, and users are solely responsible for the legality of the files they choose to upload or download.
This project is intended for educational and personal use only.

---
## 📄 License

This is a source-available project.  
The code may be viewed and studied, but **not reused, modified, or redistributed** in any form without written permission.  
See [LICENSE](./LICENSE) for more details.
