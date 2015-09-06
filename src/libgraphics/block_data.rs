/// Tile numbers used to display a particular block.
#[derive(Clone, Copy)]
pub struct BlockData {
    // 0
    pub front: u16,
    pub back: u16,
    pub top: u16,
    pub bottom: u16,

    // 8
    pub light_color: (u8, u8, u8),
    pub _pad1: u8,
    pub light_radius: u16,
    pub _pad2: u16,

    // 16
}

impl BlockData {
    pub fn tile(&self, side: usize) -> u16 {
        match side {
            0 => self.front,
            1 => self.back,
            2 => self.top,
            3 => self.bottom,
            _ => panic!("invalid side number"),
        }
    }
}
