#include "providers/telegram/td_session.h"

#include <td/telegram/td_api.hpp>

#include <algorithm>
#include <filesystem>
#include <utility>

namespace nostalgia::tg {

namespace {
template <class... Fs>
struct Overloaded : Fs... {
  using Fs::operator()...;
};
template <class... Fs>
Overloaded(Fs...) -> Overloaded<Fs...>;
}  // namespace

TdSession::TdSession(SessionConfig config) : config_(std::move(config)) {}

void TdSession::log(const std::string& text) const {
  if (on_log) on_log(text);
}

void TdSession::start() {
  std::filesystem::create_directories(config_.data_dir);
  std::filesystem::permissions(config_.data_dir, std::filesystem::perms::owner_all,
                               std::filesystem::perm_options::replace);
  if (!config_.log_file.empty()) {
    td::ClientManager::execute(td_api::make_object<td_api::setLogStream>(
        td_api::make_object<td_api::logStreamFile>(config_.log_file, 10 * 1024 * 1024, false)));
  }
  td::ClientManager::execute(td_api::make_object<td_api::setLogVerbosityLevel>(2));
  client_id_ = manager_.create_client_id();
  // TDLib starts sending updates only after the first request.
  manager_.send(client_id_, next_request_id_++, td_api::make_object<td_api::getOption>("version"));
}

void TdSession::request(RequestFactory factory, Handler handler) {
  send(Pending{std::move(factory), std::move(handler), 0});
}

void TdSession::send(Pending pending) {
  const std::uint64_t id = next_request_id_++;
  auto function = pending.factory();
  pending_.emplace(id, std::move(pending));
  ++stats_.requests;
  manager_.send(client_id_, id, std::move(function));
}

void TdSession::poll(double timeout_s) {
  const auto now = std::chrono::steady_clock::now();
  std::vector<Pending> due;
  for (auto it = retries_.begin(); it != retries_.end();) {
    if (it->due <= now) {
      due.push_back(std::move(it->pending));
      it = retries_.erase(it);
    } else {
      ++it;
    }
  }
  for (auto& p : due) send(std::move(p));

  auto response = manager_.receive(timeout_s);
  while (response.object) {
    if (response.request_id == 0) {
      ++stats_.updates;
      auto update = td::move_tl_object_as<td_api::Update>(std::move(response.object));
      if (update->get_id() == td_api::updateAuthorizationState::ID) {
        auto& u = static_cast<td_api::updateAuthorizationState&>(*update);
        on_auth_state(std::move(u.authorization_state_));
      } else if (on_update) {
        on_update(std::move(update));
      }
    } else {
      on_response(response.request_id, std::move(response.object));
    }
    response = manager_.receive(0);
  }
}

int TdSession::parse_retry_after(const std::string& message) {
  const std::string key = "retry after ";
  const auto pos = message.find(key);
  if (pos == std::string::npos) return -1;
  try {
    return std::stoi(message.substr(pos + key.size()));
  } catch (...) {
    return -1;
  }
}

void TdSession::on_response(std::uint64_t id, td_api::object_ptr<td_api::Object> object) {
  auto it = pending_.find(id);
  if (it == pending_.end()) return;  // e.g. the initial getOption
  Pending pending = std::move(it->second);
  pending_.erase(it);

  if (object->get_id() == td_api::error::ID) {
    const auto& err = static_cast<const td_api::error&>(*object);
    ++stats_.errors;
    const int wait = err.code_ == 429 ? parse_retry_after(err.message_) : -1;
    if (wait >= 0 && pending.attempts < config_.max_flood_retries) {
      ++stats_.flood_waits;
      ++pending.attempts;
      log("flood wait: retrying in " + std::to_string(wait + 1) + " s (attempt " +
          std::to_string(pending.attempts) + "/" + std::to_string(config_.max_flood_retries) + ")");
      retries_.push_back({std::chrono::steady_clock::now() + std::chrono::seconds(wait + 1), std::move(pending)});
      return;
    }
  }
  if (pending.handler) pending.handler(std::move(object));
}

void TdSession::answer(AuthPrompt prompt, const std::string& text) {
  switch (prompt) {
    case AuthPrompt::PhoneNumber:
      request([text] { return td_api::make_object<td_api::setAuthenticationPhoneNumber>(text, nullptr); },
              [this](auto o) { if (o->get_id() == td_api::error::ID) { log("phone number rejected"); if (on_auth_prompt) on_auth_prompt(AuthPrompt::PhoneNumber); } });
      break;
    case AuthPrompt::Code:
      request([text] { return td_api::make_object<td_api::checkAuthenticationCode>(text); },
              [this](auto o) { if (o->get_id() == td_api::error::ID) { log("code rejected"); if (on_auth_prompt) on_auth_prompt(AuthPrompt::Code); } });
      break;
    case AuthPrompt::Password:
      request([text] { return td_api::make_object<td_api::checkAuthenticationPassword>(text); },
              [this](auto o) { if (o->get_id() == td_api::error::ID) { log("password rejected"); if (on_auth_prompt) on_auth_prompt(AuthPrompt::Password); } });
      break;
  }
}

void TdSession::on_auth_state(td_api::object_ptr<td_api::AuthorizationState> state) {
  td_api::downcast_call(
      *state,
      Overloaded{
          [this](td_api::authorizationStateWaitTdlibParameters&) {
            request([this] {
              return td_api::make_object<td_api::setTdlibParameters>(
                  false, config_.data_dir, "", config_.db_key, true, true, true, false, config_.api_id,
                  config_.api_hash, "en", "Desktop", "Linux", "1.0");
            });
          },
          [this](td_api::authorizationStateWaitPhoneNumber&) {
            if (on_auth_prompt) on_auth_prompt(AuthPrompt::PhoneNumber);
          },
          [this](td_api::authorizationStateWaitCode&) {
            if (on_auth_prompt) on_auth_prompt(AuthPrompt::Code);
          },
          [this](td_api::authorizationStateWaitPassword&) {
            if (on_auth_prompt) on_auth_prompt(AuthPrompt::Password);
          },
          [this](td_api::authorizationStateReady&) {
            ready_ = true;
            log("authorized");
            if (on_ready) on_ready();
          },
          [this](td_api::authorizationStateLoggingOut&) { ready_ = false; log("logging out"); },
          [this](td_api::authorizationStateClosing&) { ready_ = false; log("closing"); },
          [this](td_api::authorizationStateClosed&) { ready_ = false; closed_ = true; log("closed"); },
          [this](auto& other) {
            log("unsupported authorization state: " + std::string(td_api::to_string(other).substr(0, 60)) +
                " (finish this login in the official Telegram app, or extend TdSession)");
          }});
}

void TdSession::close() {
  request([] { return td_api::make_object<td_api::close>(); });
}

}  // namespace nostalgia::tg
