from PIL import Image

from outpost_data.consts import *
from outpost_data.util import err


class BlockDef(object):
    def __init__(self, name, shape, tiles):
        self.name = name
        self.shape = shape
        self.tile_names = tiles

        self.id = None
        self.tile_ids = None

def resolve_tile_ids(blocks, tile_id_map):
    for b in blocks:
        b.tile_ids = {}
        for side, name in b.tile_names.items():
            if name is None:
                continue

            tile_id = tile_id_map.get(name)
            if tile_id is None:
                err('block %r, side %r: no such tile: %r' % (b.name, side, name))
                continue

            b.tile_ids[side] = tile_id


def build_client_json(blocks):
    def convert(b):
        dct = {
                'shape': SHAPE_ID[b.shape],
                }
        for k in BLOCK_SIDES:
            if k in b.tile_ids:
                dct[k] = b.tile_ids[k]
        return dct

    return list(convert(b) for b in blocks)

def build_server_json(blocks):
    def convert(b):
        return {
                'name': b.name,
                'shape': b.shape,
                }

    return list(convert(b) for b in blocks)