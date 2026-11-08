using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// Physics ragdoll with 11 bodies and anatomical joint limits. Mass is distributed like a real body, the
    /// body goes rigid for a moment on a knockout (the "stiff" KO), and a ragdoll can blend back into animation
    /// so a knocked-down boxer can get up.
    /// </summary>
    public class RagdollController : MonoBehaviour
    {
        class Body
        {
            public Transform t; public Body parent; public float mass;
            public Rigidbody rb; public Joint joint;
            public int kind; // 0 root, 1 spine, 2 head, 3 shoulder, 4 elbow, 5 hip, 6 knee
        }

        HumanoidRig rig;
        readonly List<Body> bodies = new List<Body>();
        public bool Active { get; private set; }
        public bool Detached { get; private set; }
        public Rigidbody HipsBody => bodies.Count > 0 ? bodies[0].rb : null;
        float stiffT;
        // recovery blending
        Transform[] blendBones;
        Quaternion[] snap;
        Vector3 snapHipsPos;
        float blendT = -1f, blendDur = 0.6f;

        public void Init(HumanoidRig r)
        {
            rig = r;
            var hips = Add(r.hips, null, 0.15f, 0);
            var chest = Add(r.chest, hips, 0.27f, 1);
            Add(r.head, chest, 0.075f, 2);
            var ul = Add(r.shoulderL, chest, 0.03f, 3); Add(r.elbowL, ul, 0.025f, 4);
            var ur = Add(r.shoulderR, chest, 0.03f, 3); Add(r.elbowR, ur, 0.025f, 4);
            var tl = Add(r.thighL, hips, 0.11f, 5); Add(r.kneeL, tl, 0.06f, 6);
            var tr = Add(r.thighR, hips, 0.11f, 5); Add(r.kneeR, tr, 0.06f, 6);
            blendBones = new[] { r.hips, r.torso, r.chest, r.neck, r.head, r.shoulderL, r.elbowL, r.handL, r.shoulderR, r.elbowR, r.handR, r.thighL, r.kneeL, r.ankleL, r.thighR, r.kneeR, r.ankleR };
            snap = new Quaternion[blendBones.Length];
        }

        Body Add(Transform t, Body parent, float massFrac, int kind)
        {
            var b = new Body { t = t, parent = parent, mass = massFrac * 75f, kind = kind };
            bodies.Add(b);
            return b;
        }

        /// <summary>Turns the rig into physics. detach = leave the owner behind (corpses).</summary>
        public void Activate(Vector3 impulse, Vector3 point, bool detach, float stiffness = 0.3f)
        {
            if (Active) return;
            Active = true;
            blendT = -1f;
            if (detach && !Detached) { Detached = true; rig.hips.SetParent(null, true); }
            var playerCol = Game.Player != null ? Game.Player.GetComponent<CharacterController>() : null;
            var playerVel = Vector3.zero;
            foreach (var b in bodies)
            {
                b.rb = b.t.gameObject.GetOrAdd<Rigidbody>();
                b.rb.isKinematic = false;
                b.rb.useGravity = true;
                b.rb.mass = b.mass;
                Util.SetDrag(b.rb, 0.05f, 4f);
                b.rb.interpolation = RigidbodyInterpolation.Interpolate;
                b.rb.collisionDetectionMode = b.kind <= 2 ? CollisionDetectionMode.ContinuousSpeculative : CollisionDetectionMode.Discrete;
                b.rb.solverIterations = 14;
                b.rb.solverVelocityIterations = 4;
                b.rb.maxAngularVelocity = 25f;
            }
            foreach (var b in bodies)
            {
                if (b.parent == null) continue;
                var j = b.t.gameObject.AddComponent<CharacterJoint>();
                j.connectedBody = b.parent.rb;
                j.enableProjection = true;
                j.projectionDistance = 0.05f;
                j.projectionAngle = 15f;
                switch (b.kind)
                {
                    case 1: Limits(j, Vector3.up, Vector3.right, -22f, 22f, 28f, 18f); break;   // spine
                    case 2: Limits(j, Vector3.up, Vector3.right, -55f, 55f, 42f, 30f); break;   // neck
                    case 3: Limits(j, Vector3.down, Vector3.right, -45f, 45f, 85f, 85f); break; // shoulder
                    case 4: Limits(j, Vector3.right, Vector3.forward, -4f, 140f, 4f, 8f); break; // elbow (flexion = +twist)
                    case 5: Limits(j, Vector3.right, Vector3.forward, -25f, 95f, 32f, 18f); break; // hip (flexion = +twist)
                    case 6: Limits(j, Vector3.right, Vector3.forward, -138f, 4f, 3f, 4f); break; // knee (flexion = -twist)
                }
                b.joint = j;
            }
            var cols = rig.hips.GetComponentsInChildren<Collider>();
            foreach (var c in cols)
            {
                if (playerCol != null) Physics.IgnoreCollision(c, playerCol);
                c.enabled = true;
            }
            // no self collision: overlapping limbs in a guard pose would otherwise explode apart
            for (int i = 0; i < cols.Length; i++)
                for (int j = i + 1; j < cols.Length; j++) Physics.IgnoreCollision(cols[i], cols[j]);
            // inherit current animation velocity a little and apply the hit
            var hit = Nearest(point);
            hit.rb.AddForceAtPosition(impulse, point, ForceMode.Impulse);
            bodies[0].rb.AddForce(impulse * 0.25f, ForceMode.Impulse);
            stiffT = stiffness;
            SetMuscleTone(stiffness > 0f ? 18f : 4f);
        }

        static void Limits(CharacterJoint j, Vector3 axis, Vector3 swingAxis, float lowTwist, float highTwist, float swing1, float swing2)
        {
            j.axis = axis; j.swingAxis = swingAxis;
            var lo = j.lowTwistLimit; lo.limit = lowTwist; lo.bounciness = 0f; j.lowTwistLimit = lo;
            var hi = j.highTwistLimit; hi.limit = highTwist; hi.bounciness = 0f; j.highTwistLimit = hi;
            var s1 = j.swing1Limit; s1.limit = swing1; j.swing1Limit = s1;
            var s2 = j.swing2Limit; s2.limit = swing2; j.swing2Limit = s2;
            var spring = j.twistLimitSpring; spring.spring = 0f; spring.damper = 6f; j.twistLimitSpring = spring;
            var ss = j.swingLimitSpring; ss.spring = 0f; ss.damper = 6f; j.swingLimitSpring = ss;
        }

        void SetMuscleTone(float angularDrag)
        {
            foreach (var b in bodies) if (b.rb != null) Util.SetDrag(b.rb, 0.05f, angularDrag);
        }

        Body Nearest(Vector3 p)
        {
            Body best = bodies[0]; float bd = float.MaxValue;
            foreach (var b in bodies)
            {
                float d = (b.t.position - p).sqrMagnitude;
                if (d < bd) { bd = d; best = b; }
            }
            return best;
        }

        public void Push(Vector3 impulse, Vector3 point)
        {
            if (!Active) return;
            var b = Nearest(point);
            if (b.rb != null) b.rb.AddForceAtPosition(impulse, point, ForceMode.Impulse);
        }

        public Vector3 HipsVelocity => Active && bodies[0].rb != null ? Util.GetVelocity(bodies[0].rb) : Vector3.zero;
        public bool Settled => Active && HipsVelocity.sqrMagnitude < 0.04f;

        /// <summary>Face up (true) or face down, from the chest orientation.</summary>
        public bool FaceUp => rig.chest.forward.y > 0f;

        /// <summary>
        /// Ends the ragdoll and blends back into animation. The rig root is moved under the hips and turned so the
        /// character gets up where it fell.
        /// </summary>
        public void Recover(Transform root, float floorY, float blendTime)
        {
            if (!Active || Detached) return;
            var hipsPos = rig.hips.position;
            var fwd = rig.chest.up; // lying down: the spine axis points where the head is
            fwd.y = 0f;
            if (fwd.sqrMagnitude < 0.001f) fwd = root.forward;
            fwd.Normalize();
            // remember world rotations, then strip physics
            var worldRot = new Quaternion[blendBones.Length];
            for (int i = 0; i < blendBones.Length; i++) worldRot[i] = blendBones[i].rotation;
            foreach (var b in bodies)
            {
                if (b.joint != null) DestroyImmediate(b.joint);
                b.joint = null;
            }
            foreach (var b in bodies)
            {
                if (b.rb != null) { b.rb.isKinematic = true; b.rb.detectCollisions = false; Destroy(b.rb); }
                b.rb = null;
            }
            foreach (var c in rig.hips.GetComponentsInChildren<Collider>()) c.enabled = true;
            // face the way the feet point so the get-up reads naturally (feet are opposite the head)
            root.position = new Vector3(hipsPos.x, floorY, hipsPos.z);
            root.rotation = Quaternion.LookRotation(-fwd, Vector3.up);
            for (int i = 0; i < blendBones.Length; i++) blendBones[i].rotation = worldRot[i];
            rig.hips.position = hipsPos;
            for (int i = 0; i < blendBones.Length; i++) snap[i] = blendBones[i].localRotation;
            snapHipsPos = rig.hips.localPosition;
            Active = false;
            rig.ragdolled = false;
            blendDur = Mathf.Max(0.05f, blendTime);
            blendT = 0f;
        }

        public bool Blending => blendT >= 0f;

        /// <summary>Called by the rig after the animation pose has been written.</summary>
        public void LateTick(float dt)
        {
            if (Active && stiffT > 0f)
            {
                stiffT -= dt;
                if (stiffT <= 0f) SetMuscleTone(1.2f);
            }
            if (blendT < 0f) return;
            blendT += dt / blendDur;
            float w = Mathf.Clamp01(blendT);
            w = w * w * (3f - 2f * w);
            for (int i = 0; i < blendBones.Length; i++) blendBones[i].localRotation = Quaternion.Slerp(snap[i], blendBones[i].localRotation, w);
            rig.hips.localPosition = Vector3.Lerp(snapHipsPos, rig.hips.localPosition, w);
            if (blendT >= 1f) blendT = -1f;
        }
    }
}
