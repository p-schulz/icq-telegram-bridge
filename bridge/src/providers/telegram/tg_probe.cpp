// tg-probe: M2 standalone Telegram probe. No ICQ involved.
//
// Environment:  TG_API_ID, TG_API_HASH   (from my.telegram.org; keep outside the repo)
//               TG_DATA_DIR              (default ~/.local/share/nostalgia-sim/tdlib)
//               TG_DB_KEY                (optional database encryption key)
// Options:      --run-for-minutes N      exit cleanly after N minutes (soak test)
//               --heartbeat-seconds N    status line interval, default 60
// Commands on stdin:
//   me | contacts | chats [N] | send <chat_id> <text...> | typing <chat_id> [off] | stats | quit | logout
#include <termios.h>
#include <unistd.h>

#include <td/telegram/td_api.hpp>

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <ctime>
#include <deque>
#include <iostream>
#include <map>
#include <mutex>
#include <optional>
#include <sstream>
#include <thread>

#include "providers/telegram/td_session.h"

namespace tg = nostalgia::tg;
namespace td_api = tg::td_api;

namespace {

std::atomic<bool> g_stop{false};
void on_signal(int) { g_stop = true; }

template <class... Fs>
struct Overloaded : Fs... {
  using Fs::operator()...;
};
template <class... Fs>
Overloaded(Fs...) -> Overloaded<Fs...>;

std::string now_str() {
  const std::time_t t = std::time(nullptr);
  char buf[16];
  std::strftime(buf, sizeof buf, "%H:%M:%S", std::localtime(&t));
  return buf;
}

void out(const std::string& line) { std::cout << "[" << now_str() << "] " << line << std::endl; }

std::string kind_of(const td_api::Object& o) {
  const std::string s = td_api::to_string(o);
  return s.substr(0, s.find_first_of(" \n{"));
}

std::string status_str(const td_api::UserStatus& s) {
  std::string r = "unknown";
  td_api::downcast_call(
      const_cast<td_api::UserStatus&>(s),
      Overloaded{
          [&](td_api::userStatusOnline&) { r = "online"; },
          [&](td_api::userStatusOffline& o) {
            const std::time_t t = o.was_online_;
            char buf[32];
            std::strftime(buf, sizeof buf, "%Y-%m-%d %H:%M", std::localtime(&t));
            r = std::string("offline (last seen ") + buf + ")";
          },
          [&](td_api::userStatusRecently&) { r = "recently (hidden by privacy)"; },
          [&](td_api::userStatusLastWeek&) { r = "last week (hidden by privacy)"; },
          [&](td_api::userStatusLastMonth&) { r = "last month (hidden by privacy)"; },
          [&](td_api::userStatusEmpty&) { r = "empty (no info)"; }});
  return r;
}

std::string user_name(const td_api::user& u) {
  std::string n = u.first_name_;
  if (!u.last_name_.empty()) n += " " + u.last_name_;
  if (u.usernames_ && !u.usernames_->active_usernames_.empty()) n += " @" + u.usernames_->active_usernames_[0];
  return n;
}

// Reads stdin lines on a helper thread; the main loop consumes them.
class Input {
 public:
  Input() {
    thread_ = std::thread([this] {
      std::string line;
      while (std::getline(std::cin, line)) {
        std::lock_guard<std::mutex> lock(mu_);
        lines_.push_back(line);
      }
      eof_ = true;
    });
    thread_.detach();
  }
  bool pop(std::string& line) {
    std::lock_guard<std::mutex> lock(mu_);
    if (lines_.empty()) return false;
    line = std::move(lines_.front());
    lines_.pop_front();
    return true;
  }
  bool eof() const { return eof_; }

 private:
  std::mutex mu_;
  std::deque<std::string> lines_;
  std::atomic<bool> eof_{false};
  std::thread thread_;
};

void set_echo(bool on) {
  if (!isatty(STDIN_FILENO)) return;
  termios t{};
  tcgetattr(STDIN_FILENO, &t);
  if (on) t.c_lflag |= ECHO; else t.c_lflag &= ~static_cast<tcflag_t>(ECHO);
  tcsetattr(STDIN_FILENO, TCSANOW, &t);
}

std::string env_or(const char* name, const std::string& fallback) {
  const char* v = std::getenv(name);
  return v && *v ? v : fallback;
}

}  // namespace

int main(int argc, char** argv) {
  int run_for_minutes = 0;
  int heartbeat_seconds = 60;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--run-for-minutes" && i + 1 < argc) run_for_minutes = std::atoi(argv[++i]);
    else if (a == "--heartbeat-seconds" && i + 1 < argc) heartbeat_seconds = std::atoi(argv[++i]);
    else { std::cerr << "unknown argument: " << a << "\n"; return 2; }
  }

  tg::SessionConfig cfg;
  cfg.api_id = std::atoi(env_or("TG_API_ID", "0").c_str());
  cfg.api_hash = env_or("TG_API_HASH", "");
  if (cfg.api_id == 0 || cfg.api_hash.empty()) {
    std::cerr << "Set TG_API_ID and TG_API_HASH (see docs/setup-guide.md, Telegram section).\n";
    return 2;
  }
  const std::string home = env_or("HOME", ".");
  cfg.data_dir = env_or("TG_DATA_DIR", home + "/.local/share/nostalgia-sim/tdlib");
  cfg.db_key = env_or("TG_DB_KEY", "");
  cfg.log_file = cfg.data_dir + "/tdlib.log";
  std::signal(SIGINT, on_signal);
  std::signal(SIGTERM, on_signal);

  std::map<std::int64_t, std::string> users;   // id -> display name
  std::map<std::int64_t, std::string> titles;  // chat id -> title
  bool hidden_input = false;
  std::optional<tg::AuthPrompt> waiting;
  std::uint64_t incoming = 0;

  tg::TdSession session(cfg);
  session.on_log = [](const std::string& s) { out("td: " + s); };
  session.on_auth_prompt = [&](tg::AuthPrompt p) {
    waiting = p;
    switch (p) {
      case tg::AuthPrompt::PhoneNumber: std::cout << "Phone number (international format, e.g. +49...): " << std::flush; break;
      case tg::AuthPrompt::Code: std::cout << "Login code from Telegram: " << std::flush; break;
      case tg::AuthPrompt::Password: std::cout << "2FA password (hidden): " << std::flush; set_echo(false); hidden_input = true; break;
    }
  };
  session.on_ready = [&] {
    session.request([] { return td_api::make_object<td_api::getMe>(); }, [&](auto o) {
      if (o->get_id() == td_api::user::ID) out("logged in as " + user_name(static_cast<td_api::user&>(*o)));
    });
    session.request([] { return td_api::make_object<td_api::loadChats>(td_api::make_object<td_api::chatListMain>(), 50); });
  };
  session.on_update = [&](td_api::object_ptr<td_api::Update> update) {
    td_api::downcast_call(
        *update,
        Overloaded{
            [&](td_api::updateUser& u) { users[u.user_->id_] = user_name(*u.user_); },
            [&](td_api::updateNewChat& c) { titles[c.chat_->id_] = c.chat_->title_; },
            [&](td_api::updateNewMessage& m) {
              const auto& msg = *m.message_;
              if (msg.is_outgoing_) return;
              ++incoming;
              std::string who = "chat " + std::to_string(msg.chat_id_);
              if (auto it = titles.find(msg.chat_id_); it != titles.end()) who = it->second + " (" + std::to_string(msg.chat_id_) + ")";
              std::string text;
              if (msg.content_->get_id() == td_api::messageText::ID) {
                text = static_cast<const td_api::messageText&>(*msg.content_).text_->text_;
              } else {
                text = "[" + kind_of(*msg.content_) + "]";
              }
              out("MSG from " + who + ": " + text);
            },
            [&](td_api::updateUserStatus& s) {
              std::string who = std::to_string(s.user_id_);
              if (auto it = users.find(s.user_id_); it != users.end()) who = it->second + " (" + who + ")";
              out("PRESENCE " + who + ": " + status_str(*s.status_));
            },
            [&](td_api::updateChatAction& a) {
              std::string who = "chat " + std::to_string(a.chat_id_);
              if (auto it = titles.find(a.chat_id_); it != titles.end()) who = it->second;
              const bool typing = a.action_->get_id() == td_api::chatActionTyping::ID;
              const bool cancel = a.action_->get_id() == td_api::chatActionCancel::ID;
              out("TYPING " + who + ": " + (typing ? "typing" : cancel ? "stopped" : kind_of(*a.action_)));
            },
            [&](td_api::updateConnectionState& c) { out("CONNECTION " + kind_of(*c.state_)); },
            [](auto&) {}});
  };

  Input input;
  session.start();

  auto handle_command = [&](const std::string& line) {
    std::istringstream ss(line);
    std::string cmd;
    ss >> cmd;
    if (cmd.empty()) return;
    if (cmd == "quit") { g_stop = true; return; }
    if (cmd == "stats") {
      const auto& s = session.stats();
      out(std::string(session.ready() ? "ready" : "not authorized") + " requests=" + std::to_string(s.requests) +
          " errors=" + std::to_string(s.errors) + " flood_waits=" + std::to_string(s.flood_waits) +
          " updates=" + std::to_string(s.updates) + " incoming_msgs=" + std::to_string(incoming));
      return;
    }
    if (!session.ready()) { out("not authorized yet"); return; }
    if (cmd == "me") {
      session.request([] { return td_api::make_object<td_api::getMe>(); }, [&](auto o) {
        if (o->get_id() == td_api::user::ID) out("me: " + user_name(static_cast<td_api::user&>(*o)));
      });
    } else if (cmd == "contacts") {
      session.request([] { return td_api::make_object<td_api::getContacts>(); }, [&](auto o) {
        if (o->get_id() != td_api::users::ID) { out("getContacts failed"); return; }
        const auto& ids = static_cast<td_api::users&>(*o).user_ids_;
        out(std::to_string(ids.size()) + " contacts");
        for (auto id : ids) {
          session.request([id] { return td_api::make_object<td_api::getUser>(id); }, [&, id](auto u) {
            if (u->get_id() != td_api::user::ID) return;
            const auto& usr = static_cast<td_api::user&>(*u);
            users[id] = user_name(usr);
            out("  " + std::to_string(id) + "  " + user_name(usr) + "  [" + status_str(*usr.status_) + "]");
          });
        }
      });
    } else if (cmd == "chats") {
      int n = 20;
      ss >> n;
      session.request([n] { return td_api::make_object<td_api::getChats>(td_api::make_object<td_api::chatListMain>(), n); }, [&](auto o) {
        if (o->get_id() != td_api::chats::ID) { out("getChats failed"); return; }
        for (auto id : static_cast<td_api::chats&>(*o).chat_ids_) {
          session.request([id] { return td_api::make_object<td_api::getChat>(id); }, [&](auto c) {
            if (c->get_id() != td_api::chat::ID) return;
            const auto& chat = static_cast<td_api::chat&>(*c);
            titles[chat.id_] = chat.title_;
            out("  " + std::to_string(chat.id_) + "  " + chat.title_ + "  <" + kind_of(*chat.type_) + ">");
          });
        }
      });
    } else if (cmd == "send") {
      std::int64_t chat_id = 0;
      ss >> chat_id;
      std::string text;
      std::getline(ss, text);
      if (!text.empty() && text.front() == ' ') text.erase(0, 1);
      if (chat_id == 0 || text.empty()) { out("usage: send <chat_id> <text>"); return; }
      session.request([=] {
        return td_api::make_object<td_api::sendMessage>(
            chat_id, nullptr, nullptr, nullptr, nullptr,
            td_api::make_object<td_api::inputMessageText>(
                td_api::make_object<td_api::formattedText>(text, std::vector<td_api::object_ptr<td_api::textEntity>>()), nullptr, false));
      }, [&](auto o) { out(o->get_id() == td_api::error::ID ? "send failed: " + static_cast<td_api::error&>(*o).message_ : "queued"); });
    } else if (cmd == "typing") {
      std::int64_t chat_id = 0;
      std::string mode;
      ss >> chat_id >> mode;
      const bool off = mode == "off";
      session.request([=] {
        return td_api::make_object<td_api::sendChatAction>(
            chat_id, nullptr, "",
            off ? td_api::object_ptr<td_api::ChatAction>(td_api::make_object<td_api::chatActionCancel>())
                : td_api::object_ptr<td_api::ChatAction>(td_api::make_object<td_api::chatActionTyping>()));
      });
    } else if (cmd == "logout") {
      session.request([] { return td_api::make_object<td_api::logOut>(); });
    } else {
      out("commands: me contacts chats [N] send <chat_id> <text> typing <chat_id> [off] stats quit logout");
    }
  };

  const auto started = std::chrono::steady_clock::now();
  auto next_heartbeat = started + std::chrono::seconds(heartbeat_seconds);
  bool closing = false;
  while (!session.closed()) {
    session.poll(0.25);

    std::string line;
    while (input.pop(line)) {
      if (waiting) {
        const auto p = *waiting;
        waiting.reset();
        if (hidden_input) { set_echo(true); hidden_input = false; std::cout << "\n"; }
        session.answer(p, line);
      } else {
        handle_command(line);
      }
    }

    const auto now = std::chrono::steady_clock::now();
    if (heartbeat_seconds > 0 && now >= next_heartbeat) {
      next_heartbeat = now + std::chrono::seconds(heartbeat_seconds);
      handle_command("stats");
    }
    if (run_for_minutes > 0 && now - started >= std::chrono::minutes(run_for_minutes)) g_stop = true;
    if (g_stop && !closing) { closing = true; out("shutting down"); session.close(); }
  }
  if (hidden_input) set_echo(true);
  const auto& s = session.stats();
  out("summary: requests=" + std::to_string(s.requests) + " errors=" + std::to_string(s.errors) +
      " flood_waits=" + std::to_string(s.flood_waits) + " updates=" + std::to_string(s.updates) +
      " incoming_msgs=" + std::to_string(incoming));
  return 0;
}
