// TEMPORARY DEVELOPMENT SWITCH.
// AUTH UX redesign is intentionally deferred until after P18.
//
// true  = bypass application-user authentication and role route gate.
// false = restore normal authentication behavior.
//
// IMPORTANT: MUST BE false before any production release.
const bool kTemporaryAuthBypass = true;
