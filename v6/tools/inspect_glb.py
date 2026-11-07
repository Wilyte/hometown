"""Dump a GLB's structure: materials, primitive attributes, node/mesh counts, AABB.

Usage: python v6/tools/inspect_glb.py <file.glb>
"""
import json
import struct
import sys


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF", magic
    off = 12
    json_chunk = None
    bin_chunk = None
    while off < total:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            json_chunk = chunk
        elif ctype == 0x004E4942:
            bin_chunk = chunk
    return json.loads(json_chunk.decode("utf-8")), bin_chunk, total


def main(path):
    gltf, blob, total = load_glb(path)
    print(f"file={path} bytes={total}")
    print(f"generator={gltf['asset'].get('generator')} version={gltf['asset']['version']}")
    print(f"scenes={len(gltf.get('scenes', []))} nodes={len(gltf.get('nodes', []))} "
          f"meshes={len(gltf.get('meshes', []))} materials={len(gltf.get('materials', []))} "
          f"textures={len(gltf.get('textures', []))} images={len(gltf.get('images', []))} "
          f"animations={len(gltf.get('animations', []))} skins={len(gltf.get('skins', []))}")
    print(f"extensionsUsed={gltf.get('extensionsUsed')} extensionsRequired={gltf.get('extensionsRequired')}")

    attrs = {}
    tris = 0
    prim_count = 0
    accessors = gltf.get("accessors", [])
    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            prim_count += 1
            for name, idx in prim.get("attributes", {}).items():
                attrs[name] = attrs.get(name, 0) + 1
            if "indices" in prim:
                tris += accessors[prim["indices"]]["count"] // 3
            else:
                pos = prim["attributes"].get("POSITION")
                if pos is not None:
                    tris += accessors[pos]["count"] // 3
    print(f"primitives={prim_count} triangles={tris}")
    print("attributes:", attrs)

    # world-space AABB from node transforms x accessor min/max (ignores instancing)
    nodes = gltf.get("nodes", [])
    parents = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parents[c] = i

    def matmul(a, b):
        return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]

    def local_matrix(n):
        if "matrix" in n:
            m = n["matrix"]
            return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
        t = n.get("translation", [0, 0, 0])
        r = n.get("rotation", [0, 0, 0, 1])
        s = n.get("scale", [1, 1, 1])
        x, y, z, w = r
        rot = [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
            [0, 0, 0, 1],
        ]
        for row in range(3):
            for col in range(3):
                rot[row][col] *= s[col]
        rot[0][3], rot[1][3], rot[2][3] = t
        return rot

    cache = {}

    def world(i):
        if i in cache:
            return cache[i]
        m = local_matrix(nodes[i])
        if i in parents:
            m = matmul(world(parents[i]), m)
        cache[i] = m
        return m

    lo = [1e30] * 3
    hi = [-1e30] * 3
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        w = world(i)
        for prim in gltf["meshes"][n["mesh"]]["primitives"]:
            acc = accessors[prim["attributes"]["POSITION"]]
            amin, amax = acc.get("min"), acc.get("max")
            if not amin:
                continue
            for cx in (amin[0], amax[0]):
                for cy in (amin[1], amax[1]):
                    for cz in (amin[2], amax[2]):
                        p = [
                            w[r][0] * cx + w[r][1] * cy + w[r][2] * cz + w[r][3]
                            for r in range(3)
                        ]
                        for k in range(3):
                            lo[k] = min(lo[k], p[k])
                            hi[k] = max(hi[k], p[k])
    size = [hi[k] - lo[k] for k in range(3)]
    center = [(hi[k] + lo[k]) / 2 for k in range(3)]
    radius = (sum(v * v for v in size)) ** 0.5 * 0.5
    print(f"aabb min={[round(v, 3) for v in lo]} max={[round(v, 3) for v in hi]}")
    print(f"size={[round(v, 3) for v in size]} center={[round(v, 3) for v in center]} radius(half-diag)={radius:.3f}")

    for i, m in enumerate(gltf.get("materials", [])[:8]):
        pbr = m.get("pbrMetallicRoughness", {})
        print(f"material[{i}] name={m.get('name')!r} baseColor={pbr.get('baseColorFactor')} "
              f"metal={pbr.get('metallicFactor')} rough={pbr.get('roughnessFactor')} "
              f"doubleSided={m.get('doubleSided')} ext={list((m.get('extensions') or {}).keys())}")

    # sample node names
    names = [n.get("name") for n in nodes if n.get("name")]
    print(f"named nodes={len(names)} sample={names[:12]}")
    print(f"root nodes={[nodes[i].get('name') for i in gltf['scenes'][0]['nodes']]}")


if __name__ == "__main__":
    main(sys.argv[1])
