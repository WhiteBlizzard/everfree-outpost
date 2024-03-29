use std::collections::HashMap;
use std::mem::replace;

use types::*;

use world::{Inventory, InventoryAttachment};
use world::{Fragment, Hooks};
use world::ops::OpResult;


pub fn create<'d, F>(f: &mut F) -> OpResult<InventoryId>
        where F: Fragment<'d> {
    let iid = create_unchecked(f);
    f.with_hooks(|h| h.on_inventory_create(iid));
    Ok(iid)
}

pub fn create_unchecked<'d, F>(f: &mut F) -> InventoryId
        where F: Fragment<'d> {
    let iid = f.world_mut().inventories.insert(Inventory {
        contents: HashMap::new(),

        stable_id: NO_STABLE_ID,
        attachment: InventoryAttachment::World,
    }).unwrap();     // Shouldn't fail when stable_id == NO_STABLE_ID
    iid
}

pub fn destroy<'d, F>(f: &mut F,
                      iid: InventoryId) -> OpResult<()>
        where F: Fragment<'d> {
    use world::InventoryAttachment::*;
    let i = unwrap!(f.world_mut().inventories.remove(iid));

    match i.attachment {
        World => {},
        Client(cid) => {
            if let Some(c) = f.world_mut().clients.get_mut(cid) {
                c.child_inventories.remove(&iid);
            }
        },
        Entity(eid) => {
            if let Some(e) = f.world_mut().entities.get_mut(eid) {
                e.child_inventories.remove(&iid);
            }
        },
        Structure(sid) => {
            if let Some(s) = f.world_mut().structures.get_mut(sid) {
                s.child_inventories.remove(&iid);
            }
        },
    }

    f.with_hooks(|h| h.on_inventory_destroy(iid));
    Ok(())
}

pub fn attach<'d, F>(f: &mut F,
                     iid: InventoryId,
                     new_attach: InventoryAttachment) -> OpResult<InventoryAttachment>
        where F: Fragment<'d> {
    use world::InventoryAttachment::*;

    let w = f.world_mut();
    let i = unwrap!(w.inventories.get_mut(iid));

    if new_attach == i.attachment {
        return Ok(new_attach);
    }

    match new_attach {
        World => {},
        Client(cid) => {
            let c = unwrap!(w.clients.get_mut(cid),
                            "can't attach inventory to nonexistent client");
            c.child_inventories.insert(iid);
        },
        Entity(eid) => {
            let e = unwrap!(w.entities.get_mut(eid),
                            "can't attach inventory to nonexistent entity");
            e.child_inventories.insert(iid);
        },
        Structure(sid) => {
            let s = unwrap!(w.structures.get_mut(sid),
                            "can't attach inventory to nonexistent structure");
            s.child_inventories.insert(iid);
        },
    }

    let old_attach = replace(&mut i.attachment, new_attach);

    match old_attach {
        World => {},
        Client(cid) => {
            w.clients[cid].child_inventories.remove(&iid);
        },
        Entity(eid) => {
            w.entities[eid].child_inventories.remove(&iid);
        },
        Structure(sid) => {
            w.structures[sid].child_inventories.remove(&iid);
        },
    }

    Ok(old_attach)
}

/// Fails only if `iid` is not valid.
pub fn update<'d, F>(f: &mut F,
                     iid: InventoryId,
                     item_id: ItemId,
                     adjust: i16) -> OpResult<u8>
        where F: Fragment<'d> {
    use std::collections::hash_map::Entry::*;

    let (old_value, new_value) = {
        let i = unwrap!(f.world_mut().inventories.get_mut(iid));

        match i.contents.entry(item_id) {
            Vacant(e) => {
                let new_value = update_item_count(0, adjust);
                e.insert(new_value);
                (0, new_value)
            },
            Occupied(mut e) => {
                let old_value = *e.get();
                let new_value = update_item_count(old_value, adjust);
                if new_value == 0 {
                    e.remove();
                } else {
                    e.insert(new_value);
                }
                (old_value, new_value)
            },
        }
    };

    f.with_hooks(|h| h.on_inventory_update(iid, item_id, old_value, new_value));

    Ok(new_value)
}

fn update_item_count(old: u8, adjust: i16) -> u8 {
    use std::u8;
    let sum = old as i16 + adjust;
    if sum < u8::MIN as i16 {
        u8::MIN
    } else if sum > u8::MAX as i16 {
        u8::MAX
    } else {
        sum as u8
    }
}
