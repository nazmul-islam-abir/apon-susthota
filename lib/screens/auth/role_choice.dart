/// Reasons the user picked this role. Used for telemetry + to drive
/// the post-role-select routing.
///
/// Extracted from the (now-removed) `lib/screens/role_select_screen.dart`
/// so it can be shared between `RoleRouter` and any future call site
/// that needs to drive routing without depending on the screen widget.
enum RoleChoice { patient, caregiver }
