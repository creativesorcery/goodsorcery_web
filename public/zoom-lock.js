// The static error pages' copy of zoom_lock_controller.js: iOS Safari
// ignores user-scalable=no for pinches, so its gesture events are cancelled.
for (const type of ["gesturestart", "gesturechange"]) {
  document.addEventListener(type, (event) => event.preventDefault(), { passive: false })
}
