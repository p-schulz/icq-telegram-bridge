// Thin wrapper around TDLib's ClientManager: authorization state machine, request/response
// matching, and automatic retry on Telegram flood-wait (HTTP-429-style) errors.
// Single-threaded: call poll() from one thread; callbacks run inside poll().
#pragma once

#include <td/telegram/Client.h>
#include <td/telegram/td_api.h>

#include <chrono>
#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

namespace nostalgia::tg {

namespace td_api = td::td_api;

enum class AuthPrompt { PhoneNumber, Code, Password };

struct SessionConfig {
  std::int32_t api_id = 0;
  std::string api_hash;
  std::string data_dir;        // TDLib database and files; must be outside the repo
  std::string db_key;          // optional database encryption key
  std::string log_file;        // TDLib's own log, kept out of the terminal
  int max_flood_retries = 5;
};

struct Stats {
  std::uint64_t requests = 0;
  std::uint64_t errors = 0;
  std::uint64_t flood_waits = 0;
  std::uint64_t updates = 0;
};

class TdSession {
 public:
  using Handler = std::function<void(td_api::object_ptr<td_api::Object>)>;
  using RequestFactory = std::function<td_api::object_ptr<td_api::Function>()>;

  explicit TdSession(SessionConfig config);

  // Set before start().
  std::function<void(AuthPrompt)> on_auth_prompt;
  std::function<void(td_api::object_ptr<td_api::Update>)> on_update;  // everything except authorization
  std::function<void(const std::string&)> on_log;
  std::function<void()> on_ready;

  void start();
  // Process incoming TDLib data and due retries for up to timeout_s seconds.
  void poll(double timeout_s);
  // The factory is called again for each flood-wait retry. handler gets the result or a td_api::error.
  void request(RequestFactory factory, Handler handler = {});
  void answer(AuthPrompt prompt, const std::string& text);
  void close();

  bool ready() const { return ready_; }
  bool closed() const { return closed_; }
  const Stats& stats() const { return stats_; }

  // Parses "Too Many Requests: retry after 12" and returns 12, or -1.
  static int parse_retry_after(const std::string& message);

 private:
  struct Pending {
    RequestFactory factory;
    Handler handler;
    int attempts = 0;
  };
  struct Retry {
    std::chrono::steady_clock::time_point due;
    Pending pending;
  };

  void send(Pending pending);
  void on_response(std::uint64_t id, td_api::object_ptr<td_api::Object> object);
  void on_auth_state(td_api::object_ptr<td_api::AuthorizationState> state);
  void log(const std::string& text) const;

  SessionConfig config_;
  td::ClientManager manager_;
  std::int32_t client_id_ = 0;
  std::uint64_t next_request_id_ = 1;
  std::unordered_map<std::uint64_t, Pending> pending_;
  std::vector<Retry> retries_;
  bool ready_ = false;
  bool closed_ = false;
  Stats stats_;
};

}  // namespace nostalgia::tg
