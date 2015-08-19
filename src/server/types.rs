use std::u16;
use std::i64;
use libphysics::CHUNK_BITS;

pub use libphysics::v3::{V2, V3, Vn, scalar, Region, Region2};

pub use util::stable_id_map::Stable;

pub type LocalTime = u16;
pub type LocalCoord = u16;

pub type Time = i64;
pub type Duration = u16;
pub type Coord = i32;

macro_rules! mk_id_newtypes {
    ( $($name:ident($inner:ty);)* ) => {
        $(
            #[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
            pub struct $name(pub $inner);

            impl $name {
                pub fn unwrap(self) -> $inner {
                    let $name(x) = self;
                    x
                }
            }
        )*
    };
}

mk_id_newtypes! {
    WireId(u16);
    ClientId(u16);
    EntityId(u32);
    InventoryId(u32);
    PlaneId(u32);
    TerrainChunkId(u32);
    StructureId(u32);
}

pub const PLANE_LIMBO: PlaneId = PlaneId(0);
pub const STABLE_PLANE_LIMBO: Stable<PlaneId> = const_Stable!(1);
pub const PLANE_FOREST: PlaneId = PlaneId(1);
pub const STABLE_PLANE_FOREST: Stable<PlaneId> = const_Stable!(2);

pub const CONTROL_WIRE_ID: WireId = WireId(0);

pub type StableId = u64;

pub type AnimId = u16;
pub type BlockId = u16;
pub type ItemId = u16;
pub type RecipeId = u16;
pub type TileId = u16;
pub type TemplateId = u32;

pub const DURATION_MAX: Duration = u16::MAX;
pub const TIME_MIN: Time = i64::MIN;

pub const CHUNK_TOTAL: usize = 1 << (3 * CHUNK_BITS);
pub type BlockChunk = [BlockId; CHUNK_TOTAL];

// 0 is always the BlockId of "empty" (no appearance; empty shape)
pub static EMPTY_CHUNK: BlockChunk = [0; CHUNK_TOTAL];
// 1 is always the BlockId of "placeholder" (no appearance; solid shape)
pub static PLACEHOLDER_CHUNK: BlockChunk = [1; CHUNK_TOTAL];


/// Trait for converting from local to global.
///
/// Converting from global coordinates to local ones throws away information.  That information is
/// recovered by consulting a "base", a global coordinate value that is known to be near the
/// original global value.  "Near" means within half the range of the local coordinate type, so if
/// local coordinates are `u16`, then "near" means within 32k (2^15) in either direction.
pub trait ToGlobal {
    type Global;
    fn to_global(self, base: <Self as ToGlobal>::Global) -> <Self as ToGlobal>::Global;
}

impl ToGlobal for LocalTime {
    type Global = Time;

    #[inline]
    fn to_global(self, base: Time) -> Time {
        let delta = self.wrapping_sub(base as u16);
        base + delta as i16 as i64
    }
}


pub trait ToLocal {
    type Local;
    fn to_local(self) -> <Self as ToLocal>::Local;
}

impl ToLocal for Time {
    type Local = LocalTime;

    #[inline(always)]
    fn to_local(self) -> LocalTime {
        self as LocalTime
    }
}