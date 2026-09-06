// Historical compatibility marker only.
//
// P18 production authority closure removed the runtime bypass from AppRoutes.
// This constant remains false so any stale external reference fails closed.
const bool kTemporaryAuthBypass = false;
