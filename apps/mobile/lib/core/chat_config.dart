/// Single source of truth for the chat rollout.
///
/// Chat is OFF by default: no Firebase initialization, no token request, no
/// chat buttons and no chat routes. Flip this to true only after the Firebase
/// console setup, custom-token endpoint and RTDB rules are ready.
const bool kChatEnabled = false;
