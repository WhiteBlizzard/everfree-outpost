use std::collections::{HashMap, HashSet};

use physics::CHUNK_BITS;
use physics::v3::{Vn, V2, V3};

use data::Data;
use input::InputBits;
use types::*;
use util::{StableIdMap, Stable};
use view::ViewState;

use self::object::{Object, ObjectRef, ObjectRefMut};

macro_rules! bad {
    ($ok:expr, $msg:expr) => { bad!($ok, $msg,) };
    ($ok:expr, $msg:expr, $($extra:tt)*) => {{
        error!(concat!("broken World invariant: ", $msg), $($extra)*);
        $ok = false;
    }};
}

macro_rules! check {
    ($ok:expr, $cond:expr, $($args:tt)*) => {
        if $cond {
            bad!($ok, $($args)*);
        }
    };
}

mod object;
mod ops;
mod debug;


#[derive(Copy, PartialEq, Eq, Show)]
pub enum EntityAttachment {
    World,
    Chunk,
    Client(ClientId),
}

#[derive(Copy, PartialEq, Eq, Show)]
enum StructureAttachment {
    World,
    Chunk,
}

#[derive(Copy, PartialEq, Eq, Show)]
enum InventoryAttachment {
    World,
    Client(ClientId),
    Entity(EntityId),
    Structure(StructureId),
}


pub struct Client {
    pawn: Option<EntityId>,
    current_input: InputBits,
    chunk_offset: (u8, u8),
    view_state: ViewState,

    stable_id: StableId,
    child_entities: HashSet<EntityId>,
    child_inventories: HashSet<InventoryId>,
}
impl_IntrusiveStableId!(Client, stable_id);

struct TerrainChunk {
    blocks: [BlockId; 1 << (3 * CHUNK_BITS)],
}

pub struct Motion;

pub struct Entity {
    motion: Motion,
    anim: AnimId,
    facing: V3,

    stable_id: StableId,
    attachment: EntityAttachment,
    child_inventories: HashSet<InventoryId>,
}
impl_IntrusiveStableId!(Entity, stable_id);

struct Structure {
    pos: V3,
    offset: (u8, u8, u8),
    template: TemplateId,

    stable_id: StableId,
    attachment: StructureAttachment,
    child_inventories: HashSet<InventoryId>,
}
impl_IntrusiveStableId!(Structure, stable_id);

struct Inventory {
    contents: HashMap<String, u8>,

    stable_id: StableId,
    attachment: InventoryAttachment,
}
impl_IntrusiveStableId!(Inventory, stable_id);


struct World<'d> {
    data: &'d Data,

    clients: StableIdMap<ClientId, Client>,
    terrain_chunks: HashMap<V2, TerrainChunk>,
    entities: StableIdMap<EntityId, Entity>,
    structures: StableIdMap<StructureId, Structure>,
    inventories: StableIdMap<InventoryId, Inventory>,

    structures_by_chunk: HashMap<V2, HashSet<StructureId>>,
}

pub enum Update {
    ClientViewReset(ClientId),
}

impl<'d> World<'d> {
    pub fn new(data: &'d Data) -> World<'d> {
        World {
            data: data,

            clients: StableIdMap::new(),
            terrain_chunks: HashMap::new(),
            entities: StableIdMap::new(),
            structures: StableIdMap::new(),
            inventories: StableIdMap::new(),

            structures_by_chunk: HashMap::new(),
        }
    }

    pub fn record(&mut self, update: Update) {
        // TODO
    }
}

macro_rules! obj_methods {
    ($obj_ty:ty,
     $id_name:ident: $id_ty:ty => $table:ident . get ( $lookup_arg:expr ),
     $get_obj:ident, $get_obj_mut:ident, $obj:ident, $obj_mut:ident) => {
        impl<'d> World<'d> {
            pub fn $get_obj<'a>(&'a self,
                                $id_name: $id_ty) -> Option<ObjectRef<'a, 'd, $obj_ty>> {
                let obj = match self.$table.get($lookup_arg) {
                    None => return None,
                    Some(x) => x,
                };

                Some(ObjectRef {
                    world: self,
                    id: $id_name,
                    obj: obj,
                })
            }

            pub fn $get_obj_mut<'a>(&'a mut self,
                                    $id_name: $id_ty) -> Option<ObjectRefMut<'a, 'd, $obj_ty>> {
                match self.$table.get($lookup_arg) {
                    None => return None,
                    Some(_) => {},
                }

                Some(ObjectRefMut {
                    world: self,
                    id: $id_name,
                })
            }

            pub fn $obj<'a>(&'a self, $id_name: $id_ty) -> ObjectRef<'a, 'd, $obj_ty> {
                self.$get_obj($id_name)
                    .expect(concat!("no ", stringify!($obj_ty), " with given id"))
            }

            pub fn $obj_mut<'a>(&'a mut self, $id_name: $id_ty) -> ObjectRefMut<'a, 'd, $obj_ty> {
                self.$get_obj_mut($id_name)
                    .expect(concat!("no ", stringify!($obj_ty), " with given id"))
            }
        }
    };
}

obj_methods!(Client,
             id: ClientId => clients.get(id),
             get_client, get_client_mut, client, client_mut);

obj_methods!(TerrainChunk,
             id: V2 => terrain_chunks.get(&id),
             get_terrain_chunk, get_terrain_chunk_mut, terrain_chunk, terrain_chunk_mut);

obj_methods!(Entity,
             id: EntityId => entities.get(id),
             get_entity, get_entity_mut, entity, entity_mut);

obj_methods!(Structure,
             id: StructureId => structures.get(id),
             get_structure, get_structure_mut, structure, structure_mut);

obj_methods!(Inventory,
             id: InventoryId => inventories.get(id),
             get_inventory, get_inventory_mut, inventory, inventory_mut);


impl Client {
    pub fn current_input(&self) -> InputBits {
        self.current_input
    }

    pub fn set_current_input(&mut self, new: InputBits) {
        self.current_input = new;
    }

    pub fn chunk_offset(&self) -> (u8, u8) {
        self.chunk_offset
    }

    pub fn set_chunk_offset(&mut self, new: (u8, u8)) {
        self.chunk_offset = new;
    }

    pub fn view_state(&self) -> &ViewState {
        &self.view_state
    }

    pub fn view_state_mut(&mut self) -> &mut ViewState {
        &mut self.view_state
    }
}

impl TerrainChunk {
    pub fn block(&self, idx: usize) -> BlockId {
        self.blocks[idx]
    }
}

impl Entity {
    pub fn motion(&self) -> &Motion {
        &self.motion
    }

    // No motion_mut since modifying `self.motion` affects lookup tables.

    pub fn anim(&self) -> AnimId {
        self.anim
    }

    pub fn set_anim(&mut self, new: AnimId) {
        self.anim = new;
    }

    pub fn facing(&self) -> V3 {
        self.facing
    }

    pub fn set_facing(&mut self, new: V3) {
        self.facing = new;
    }

    pub fn pos(&self, now: Time) -> V3 {
        // TODO
        V3::new(1, 2, 3)
    }

    pub fn attachment(&self) -> EntityAttachment {
        self.attachment
    }
}

impl Structure {
    pub fn pos(&self) -> V3 {
        self.pos
    }

    pub fn template_id(&self) -> TemplateId {
        self.template
    }
}
