use libc::c_int;

use physics::{TILE_SIZE, CHUNK_SIZE};
use physics::v3::{Vn, V3, scalar};

use lua::LuaState;
use types::*;
use util::StrResult;
use world::Update;
use world::object::*;

use super::{ScriptContext, get_ctx};
use super::build_type_table;
use super::traits::Userdata;
use super::traits::{check_args, FromLua, ToLua};
use super::traits::{TypeName, type_name};

macro_rules! mk_build_types_table {
    ($($ty:ty),*) => {
        pub fn build_types_table(lua: &mut LuaState) {
            lua.push_table();
            $({
                build_type_table::<$ty>(lua);
                lua.set_field(-2, <$ty as TypeName>::type_name());
            })*
        }
    }
}

mk_build_types_table!(V3, World, Client, Entity, Structure, Inventory);


macro_rules! insert_function {
    ($lua:expr, $idx:expr, $name:expr, $func:expr) => {{
        $lua.push_rust_function($func);
        $lua.set_field($idx - 1, $name);
    }}
}

macro_rules! lua_table_fns {
    ($lua:expr, $idx:expr,
        $( fn $name:ident($($arg_name:ident : $arg_ty:ty),*) -> $ret_ty:ty { $body:expr } )*) => {{
        $(
            lua_fn!(fn $name($($arg_name: $arg_ty),*) -> $ret_ty { $body });
            insert_function!($lua, $idx, stringify!($name), $name);
        )*
    }}
}

macro_rules! lua_table_ctx_fns {
    ($lua:expr, $idx:expr, $ctx_name:ident,
        $( fn $name:ident($($arg_name:ident : $arg_ty:ty),*)
                -> $ret_ty:ty { $body:expr } )*) => {{
        $(
            lua_ctx_fn!(fn $name($ctx_name, $($arg_name: $arg_ty),*) -> $ret_ty { $body });
            insert_function!($lua, $idx, stringify!($name), $name);
        )*
    }}
}


impl_type_name!(V3);
impl_metatable_key!(V3);

impl Userdata for V3 {
    fn populate_table(lua: &mut LuaState) {
        lua_table_fns! {
            lua, -1,

            fn x(ud: V3) -> i32 { ud.x }
            fn y(ud: V3) -> i32 { ud.y }
            fn z(ud: V3) -> i32 { ud.z }

            fn new(x: i32, y: i32, z: i32) -> V3 { V3::new(x, y, z) }

            fn abs(ud: V3) -> V3 { ud.abs() }
            fn extract(ud: V3) -> (i32, i32, i32) { (ud.x, ud.y, ud.z) }

            fn pixel_to_tile(ud: V3) -> V3 {
                ud.div_floor(scalar(TILE_SIZE))
            }

            fn tile_to_chunk(ud: V3) -> V3 {
                ud.div_floor(scalar(CHUNK_SIZE))
            }
        }
    }

    fn populate_metatable(lua: &mut LuaState) {
        lua_table_fns! {
            lua, -1,

            fn __add(a: V3, b: V3) -> V3 { a + b }
            fn __sub(a: V3, b: V3) -> V3 { a - b }
            fn __mul(a: V3, b: V3) -> V3 { a * b }
            fn __div(a: V3, b: V3) -> V3 { a / b }
            fn __mod(a: V3, b: V3) -> V3 { a % b }
        }
    }
}


#[derive(Copy)]
pub struct World;

impl_type_name!(World);
impl_metatable_key!(World);

impl Userdata for World {
    fn populate_table(lua: &mut LuaState) {
        lua_table_ctx_fns! {
            lua, -1, ctx,

            fn find_structure_at_point(_w: &World, pos: V3) -> Option<Structure> {{
                let chunk = pos.reduce().div_floor(scalar(CHUNK_SIZE));
                for s in ctx.world.chunk_structures(chunk) {
                    if s.bounds().contains(pos) {
                        return Some(Structure { id: s.id() });
                    }
                }
                None
            }}

            fn create_entity(_w: &World, pos: V3, anim: AnimId) -> StrResult<Entity> {
                ctx.world.create_entity(pos, anim)
                   .map(|e| Entity { id: e.id() })
            }

            fn create_structure(_w: &World, pos: V3, template_id: u32) -> StrResult<Structure> {
                ctx.world.create_structure(pos, template_id)
                   .map(|s| Structure { id: s.id() })
            }

            fn create_inventory(_w: &World) -> StrResult<Inventory> {
                ctx.world.create_inventory()
                   .map(|i| Inventory { id: i.id() })
            }
        }
    }
}


#[derive(Copy)]
pub struct Client {
    pub id: ClientId,
}

impl_type_name!(Client);
impl_metatable_key!(Client);

impl Userdata for Client {
    fn populate_table(lua: &mut LuaState) {
        lua_table_fns! {
            lua, -1,

            fn world(_c: &Client) -> World { World }
            fn id(c: &Client) -> u16 { c.id.unwrap() }
        }

        lua_table_ctx_fns! {
            lua, -1, ctx,

            fn pawn(c: &Client) -> Option<Entity> {
                ctx.world.get_client(c.id)
                   .and_then(|c| c.pawn_id())
                   .map(|eid| Entity { id: eid })
            }

            fn set_pawn(c: &Client, e: &Entity) -> StrResult<()> {{
                let mut c = unwrap!(ctx.world.get_client_mut(c.id));
                try!(c.set_pawn(Some(e.id)));
                Ok(())
            }}

            fn clear_pawn(c: &Client) -> StrResult<()> {{
                let mut c = unwrap!(ctx.world.get_client_mut(c.id));
                try!(c.set_pawn(None));
                Ok(())
            }}

            fn open_inventory(c: &Client, i: &Inventory) -> StrResult<()> {{
                // CHeck inputs are valid.
                unwrap!(ctx.world.get_client(c.id));
                unwrap!(ctx.world.get_inventory(i.id));

                ctx.world.record(Update::ClientShowInventory(c.id, i.id));
                Ok(())
            }}
        }
    }
}


#[derive(Copy)]
pub struct Entity {
    pub id: EntityId,
}

impl_type_name!(Entity);
impl_metatable_key!(Entity);

impl Userdata for Entity {
    fn populate_table(lua: &mut LuaState) {
        use world::EntityAttachment;

        lua_table_fns! {
            lua, -1,

            fn world(_e: &Entity) -> World { World }
            fn id(e: &Entity) -> u32 { e.id.unwrap() }
        }

        lua_table_ctx_fns! {
            lua, -1, ctx,

            fn destroy(e: &Entity) -> StrResult<()> {
                ctx.world.destroy_entity(e.id)
            }

            fn pos(e: &Entity) -> Option<V3> {
                ctx.world.get_entity(e.id).map(|e| e.pos(ctx.now))
            }

            fn facing(e: &Entity) -> Option<V3> {
                ctx.world.get_entity(e.id).map(|e| e.facing())
            }

            // TODO: come up with a lua representation of attachment so we can unify these methods
            // and also return the previous attachment (like the underlying op does)
            fn attach_to_world(e: &Entity) -> StrResult<()> {{
                let mut e = unwrap!(ctx.world.get_entity_mut(e.id));
                try!(e.set_attachment(EntityAttachment::World));
                Ok(())
            }}

            fn attach_to_client(e: &Entity, c: &Client) -> StrResult<()> {{
                let mut e = unwrap!(ctx.world.get_entity_mut(e.id));
                try!(e.set_attachment(EntityAttachment::Client(c.id)));
                Ok(())
            }}
        }
    }
}


#[derive(Copy)]
pub struct Structure {
    pub id: StructureId,
}

impl Structure {
    fn world(&self) -> World {
        World
    }

    fn id(&self) -> i32 {
        self.id.unwrap() as i32
    }

    fn pos(&self, ctx: &ScriptContext) -> Option<V3> {
        ctx.world.get_structure(self.id)
           .map(|s| s.pos())
    }
}

impl_type_name!(Structure);
impl_metatable_key!(Structure);

impl Userdata for Structure {
    fn populate_table(lua: &mut LuaState) {
        use world::StructureAttachment;

        lua_table_fns! {
            lua, -1,

            fn world(_s: &Structure) -> World { World }
            fn id(s: &Structure) -> u32 { s.id.unwrap() }
        }

        lua_table_ctx_fns! {
            lua, -1, ctx,

            fn destroy(s: &Structure) -> StrResult<()> {
                ctx.world.destroy_structure(s.id)
            }

            fn pos(s: &Structure) -> Option<V3> {
                ctx.world.get_structure(s.id)
                   .map(|s| s.pos())
            }

            fn size(s: &Structure) -> Option<V3> {
                ctx.world.get_structure(s.id)
                   .map(|s| s.size())
            }

            fn template_id(s: &Structure) -> Option<u32> {
                ctx.world.get_structure(s.id)
                   .map(|s| s.template_id())
            }

            fn move_to(s: &Structure, new_pos: &V3) -> StrResult<()> {{
                let mut s = unwrap!(ctx.world.get_structure_mut(s.id));
                s.set_pos(*new_pos)
            }}

            fn replace(s: &Structure, new_template_name: &str) -> StrResult<()> {{
                let new_template_id =
                    unwrap!(ctx.world.data().object_templates.find_id(new_template_name),
                            "named structure template does not exist");

                let mut s = unwrap!(ctx.world.get_structure_mut(s.id));
                s.set_template_id(new_template_id)
            }}

            fn attach_to_world(s: &Structure) -> StrResult<()> {{
                let mut s = unwrap!(ctx.world.get_structure_mut(s.id));
                try!(s.set_attachment(StructureAttachment::World));
                Ok(())
            }}

            fn attach_to_chunk(s: &Structure) -> StrResult<()> {{
                let mut s = unwrap!(ctx.world.get_structure_mut(s.id));
                try!(s.set_attachment(StructureAttachment::Chunk));
                Ok(())
            }}
        }

        insert_function!(lua, -1, "template", structure_template);
    }
}

fn structure_template(mut lua: LuaState) -> c_int {
    let result = {
        unsafe { check_args::<&Structure>(&mut lua, "template") };
        let ctx = unsafe { get_ctx(&mut lua) };
        let s: &Structure = unsafe { FromLua::from_lua(&lua, 1) };

        ctx.world.get_structure(s.id)
           .map(|s| s.template_id())
           .and_then(|id| ctx.world.data().object_templates.get_template(id))
           .map(|t| &*t.name)
    };
    lua.pop(1);
    result.to_lua(&mut lua);
    1
}


#[derive(Copy)]
pub struct Inventory {
    pub id: InventoryId,
}

impl_type_name!(Inventory);
impl_metatable_key!(Inventory);

impl Userdata for Inventory {
    fn populate_table(lua: &mut LuaState) {
        use world::InventoryAttachment;

        lua_table_fns! {
            lua, -1,

            fn world(_i: &Inventory) -> World { World }
            fn id(i: &Inventory) -> u32 { i.id.unwrap() }
        }

        lua_table_ctx_fns! {
            lua, -1, ctx,

            fn destroy(i: &Inventory) -> StrResult<()> {
                ctx.world.destroy_inventory(i.id)
            }

            fn count(i: &Inventory, name: &str) -> Option<u8> {
                ctx.world.get_inventory(i.id).map(|i| i.count(name))
            }

            fn update(i: &Inventory, name: &str, adjust: i16) -> StrResult<u8> {{
                let mut i = unwrap!(ctx.world.get_inventory_mut(i.id));
                i.update(name, adjust)
            }}

            fn attach_to_world(i: &Inventory) -> StrResult<()> {{
                let mut i = unwrap!(ctx.world.get_inventory_mut(i.id));
                try!(i.set_attachment(InventoryAttachment::World));
                Ok(())
            }}

            fn attach_to_client(i: &Inventory, c: &Client) -> StrResult<()> {{
                let mut i = unwrap!(ctx.world.get_inventory_mut(i.id));
                try!(i.set_attachment(InventoryAttachment::Client(c.id)));
                Ok(())
            }}

            fn attach_to_entity(i: &Inventory, e: &Entity) -> StrResult<()> {{
                let mut i = unwrap!(ctx.world.get_inventory_mut(i.id));
                try!(i.set_attachment(InventoryAttachment::Entity(e.id)));
                Ok(())
            }}

            fn attach_to_structure(i: &Inventory, s: &Structure) -> StrResult<()> {{
                let mut i = unwrap!(ctx.world.get_inventory_mut(i.id));
                try!(i.set_attachment(InventoryAttachment::Structure(s.id)));
                Ok(())
            }}
        }
    }
}
