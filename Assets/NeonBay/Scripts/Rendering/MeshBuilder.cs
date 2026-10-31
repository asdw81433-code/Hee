using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace NeonBay
{
    /// <summary>
    /// Accumulates geometry grouped by material and produces one combined mesh with sub-meshes.
    /// Used to keep the whole city at a few draw calls per chunk.
    /// </summary>
    public class MeshBuilder
    {
        readonly List<Vector3> verts = new List<Vector3>(4096);
        readonly List<Vector3> norms = new List<Vector3>(4096);
        readonly List<Vector2> uvs = new List<Vector2>(4096);
        readonly List<Material> mats = new List<Material>();
        readonly List<List<int>> tris = new List<List<int>>();

        public int VertexCount => verts.Count;
        public bool Empty => verts.Count == 0;

        List<int> Sub(Material m)
        {
            int i = mats.IndexOf(m);
            if (i < 0) { mats.Add(m); tris.Add(new List<int>(2048)); i = mats.Count - 1; }
            return tris[i];
        }

        /// <summary>Quad with corners a,b,c,d in clockwise order when viewed from the front.</summary>
        public void Quad(Material m, Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector2 ua, Vector2 ub, Vector2 uc, Vector2 ud)
        {
            var t = Sub(m);
            int i = verts.Count;
            var n = Vector3.Cross(b - a, d - a).normalized;
            verts.Add(a); verts.Add(b); verts.Add(c); verts.Add(d);
            norms.Add(n); norms.Add(n); norms.Add(n); norms.Add(n);
            uvs.Add(ua); uvs.Add(ub); uvs.Add(uc); uvs.Add(ud);
            t.Add(i); t.Add(i + 1); t.Add(i + 2);
            t.Add(i); t.Add(i + 2); t.Add(i + 3);
        }

        /// <summary>Upward facing rectangle on the XZ plane, UVs in world meters / tile.</summary>
        public void Floor(Material m, float x0, float z0, float x1, float z1, float y, Vector2 tile, bool rotateUV = false)
        {
            Vector2 U(float x, float z) => rotateUV ? new Vector2(z / tile.x, x / tile.y) : new Vector2(x / tile.x, z / tile.y);
            Quad(m, new Vector3(x0, y, z0), new Vector3(x0, y, z1), new Vector3(x1, y, z1), new Vector3(x1, y, z0),
                U(x0, z0), U(x0, z1), U(x1, z1), U(x1, z0));
        }

        /// <summary>Rectangle with UV 0..1 mapped explicitly (used for roads where u spans the road width).</summary>
        public void FloorUV(Material m, Vector3 a, Vector3 b, Vector3 c, Vector3 d, Rect uv)
        {
            Quad(m, a, b, c, d, new Vector2(uv.xMin, uv.yMin), new Vector2(uv.xMin, uv.yMax), new Vector2(uv.xMax, uv.yMax), new Vector2(uv.xMax, uv.yMin));
        }

        /// <summary>
        /// Axis aligned box. Side UVs use world units divided by 'tile', with V anchored to world height
        /// so window rows line up with floors. Pass null for faces that should be skipped.
        /// </summary>
        public void Box(Vector3 min, Vector3 max, Material side, Material top, Vector2 tile, Material bottom = null, Vector2? topTile = null, float uOffset = 0f)
        {
            var tt = topTile ?? new Vector2(6, 6);
            float x0 = min.x, y0 = min.y, z0 = min.z, x1 = max.x, y1 = max.y, z1 = max.z;
            if (side != null)
            {
                float dx = x1 - x0, dz = z1 - z0;
                float v0 = y0 / tile.y, v1 = y1 / tile.y;
                // south (-z)
                Quad(side, new Vector3(x0, y0, z0), new Vector3(x0, y1, z0), new Vector3(x1, y1, z0), new Vector3(x1, y0, z0),
                    new Vector2(uOffset, v0), new Vector2(uOffset, v1), new Vector2(uOffset + dx / tile.x, v1), new Vector2(uOffset + dx / tile.x, v0));
                // north (+z)
                Quad(side, new Vector3(x1, y0, z1), new Vector3(x1, y1, z1), new Vector3(x0, y1, z1), new Vector3(x0, y0, z1),
                    new Vector2(uOffset, v0), new Vector2(uOffset, v1), new Vector2(uOffset + dx / tile.x, v1), new Vector2(uOffset + dx / tile.x, v0));
                // west (-x)
                Quad(side, new Vector3(x0, y0, z1), new Vector3(x0, y1, z1), new Vector3(x0, y1, z0), new Vector3(x0, y0, z0),
                    new Vector2(uOffset, v0), new Vector2(uOffset, v1), new Vector2(uOffset + dz / tile.x, v1), new Vector2(uOffset + dz / tile.x, v0));
                // east (+x)
                Quad(side, new Vector3(x1, y0, z0), new Vector3(x1, y1, z0), new Vector3(x1, y1, z1), new Vector3(x1, y0, z1),
                    new Vector2(uOffset, v0), new Vector2(uOffset, v1), new Vector2(uOffset + dz / tile.x, v1), new Vector2(uOffset + dz / tile.x, v0));
            }
            if (top != null) Floor(top, x0, z0, x1, z1, y1, tt);
            if (bottom != null)
                Quad(bottom, new Vector3(x0, y0, z0), new Vector3(x1, y0, z0), new Vector3(x1, y0, z1), new Vector3(x0, y0, z1),
                    new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1));
        }

        /// <summary>Box with all faces using simple 0..1 UVs (props, small details).</summary>
        public void SimpleBox(Vector3 center, Vector3 size, Material m, Quaternion? rotation = null)
        {
            var r = rotation ?? Quaternion.identity;
            var h = size * 0.5f;
            Vector3 P(float x, float y, float z) => center + r * new Vector3(x * h.x, y * h.y, z * h.z);
            var uv0 = new Vector2(0, 0); var uv1 = new Vector2(0, 1); var uv2 = new Vector2(1, 1); var uv3 = new Vector2(1, 0);
            Quad(m, P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1), uv0, uv1, uv2, uv3);
            Quad(m, P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1), P(-1, -1, 1), uv0, uv1, uv2, uv3);
            Quad(m, P(-1, -1, 1), P(-1, 1, 1), P(-1, 1, -1), P(-1, -1, -1), uv0, uv1, uv2, uv3);
            Quad(m, P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1), uv0, uv1, uv2, uv3);
            Quad(m, P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1), P(1, 1, -1), uv0, uv1, uv2, uv3);
            Quad(m, P(-1, -1, 1), P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), uv0, uv1, uv2, uv3);
        }

        /// <summary>A vertical, single sided panel facing 'normal' (signs, billboards).</summary>
        public void Panel(Material m, Vector3 center, Vector3 normal, float width, float height, Rect uv)
        {
            var right = Vector3.Cross(Vector3.up, normal).normalized;
            if (right.sqrMagnitude < 0.01f) right = Vector3.right;
            var up = Vector3.Cross(normal, right).normalized;
            var hw = right * width * 0.5f; var hh = up * height * 0.5f;
            // viewed from the front (looking along -normal), right is on the viewer's left in this convention
            Quad(m, center + hw - hh, center + hw + hh, center - hw + hh, center - hw - hh,
                new Vector2(uv.xMin, uv.yMin), new Vector2(uv.xMin, uv.yMax), new Vector2(uv.xMax, uv.yMax), new Vector2(uv.xMax, uv.yMin));
        }

        public void Cylinder(Material m, Vector3 baseCenter, float radius, float height, int segments = 10, bool caps = true)
        {
            var t = Sub(m);
            for (int s = 0; s < segments; s++)
            {
                float a0 = s / (float)segments * Mathf.PI * 2, a1 = (s + 1) / (float)segments * Mathf.PI * 2;
                var d0 = new Vector3(Mathf.Cos(a0), 0, Mathf.Sin(a0)); var d1 = new Vector3(Mathf.Cos(a1), 0, Mathf.Sin(a1));
                int i = verts.Count;
                verts.Add(baseCenter + d0 * radius); verts.Add(baseCenter + d0 * radius + Vector3.up * height);
                verts.Add(baseCenter + d1 * radius + Vector3.up * height); verts.Add(baseCenter + d1 * radius);
                norms.Add(d0); norms.Add(d0); norms.Add(d1); norms.Add(d1);
                float u0 = s / (float)segments, u1 = (s + 1) / (float)segments;
                uvs.Add(new Vector2(u0, 0)); uvs.Add(new Vector2(u0, height / 4f)); uvs.Add(new Vector2(u1, height / 4f)); uvs.Add(new Vector2(u1, 0));
                t.Add(i); t.Add(i + 1); t.Add(i + 2);
                t.Add(i); t.Add(i + 2); t.Add(i + 3);
                if (caps)
                {
                    int c = verts.Count;
                    var top = baseCenter + Vector3.up * height;
                    verts.Add(top); verts.Add(top + d0 * radius); verts.Add(top + d1 * radius);
                    norms.Add(Vector3.up); norms.Add(Vector3.up); norms.Add(Vector3.up);
                    uvs.Add(new Vector2(0.5f, 0.5f)); uvs.Add(new Vector2(0.5f + d0.x * 0.5f, 0.5f + d0.z * 0.5f)); uvs.Add(new Vector2(0.5f + d1.x * 0.5f, 0.5f + d1.z * 0.5f));
                    t.Add(c); t.Add(c + 2); t.Add(c + 1);
                }
            }
        }

        public void Clear()
        {
            verts.Clear(); norms.Clear(); uvs.Clear(); mats.Clear(); tris.Clear();
        }

        public Mesh Build(string name, out Material[] materials)
        {
            var mesh = new Mesh { name = name };
            if (verts.Count > 65000) mesh.indexFormat = IndexFormat.UInt32;
            mesh.SetVertices(verts);
            mesh.SetNormals(norms);
            mesh.SetUVs(0, uvs);
            mesh.subMeshCount = tris.Count;
            for (int i = 0; i < tris.Count; i++) mesh.SetTriangles(tris[i], i, false);
            mesh.RecalculateBounds();
            mesh.RecalculateTangents();
            materials = mats.ToArray();
            return mesh;
        }

        /// <summary>Builds the mesh into a new child GameObject. Returns null if nothing was added.</summary>
        public GameObject BuildObject(string name, Transform parent, bool castShadows = true)
        {
            if (Empty) return null;
            var mesh = Build(name, out var materials);
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.AddComponent<MeshRenderer>();
            r.sharedMaterials = materials;
            r.shadowCastingMode = castShadows ? ShadowCastingMode.On : ShadowCastingMode.Off;
            return go;
        }
    }
}
