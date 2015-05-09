// Passive data structure to track all the data needed to render the game
// world.
/** @constructor */
function Scene() {
    this.camera_pos = [0, 0];
    this.camera_size = [100, 100];
    this.sprites = null;
    this.slice_z = 16;
    this.slice_frac = 0;
}
exports.Scene = Scene;
