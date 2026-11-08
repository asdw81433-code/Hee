using UnityEngine;

namespace NeonBay
{
    /// <summary>
    /// Third-person fight camera: over-the-shoulder framing of both fighters, a broadcast side angle (B), a low
    /// knockdown angle, slow KO orbit, a close-up in the corner (so you can see the damage) and the replay orbit.
    /// Every mode runs through CameraFX for shake, kicks and FOV punches.
    /// </summary>
    public class BoxingCamera : MonoBehaviour
    {
        public Camera Cam { get; private set; }
        BoxingMatch m;
        Vector3 pos; Quaternion rot;
        float fov = 50f;
        bool init;
        float orbit;

        public static BoxingCamera Attach(BoxingMatch match, Camera cam)
        {
            var bc = match.gameObject.AddComponent<BoxingCamera>();
            bc.m = match; bc.Cam = cam;
            return bc;
        }

        void LateUpdate()
        {
            if (m == null || Cam == null || m.Red == null || m.Blue == null) return;
            float dt = Time.unscaledDeltaTime;
            var p = m.Red; var o = m.Blue;
            Vector3 ph = p.rig.head.position, oh = o.rig.head.position;
            var center = m.ring.Center;
            Vector3 wantPos, wantLook; float wantFov;
            orbit += dt * 0.25f;
            switch (m.phase)
            {
                case MatchPhase.Intro:
                    {
                        float a = orbit * 0.6f + 0.8f;
                        wantPos = center + new Vector3(Mathf.Cos(a) * 5.2f, 1.9f, Mathf.Sin(a) * 5.2f);
                        wantLook = center + Vector3.up * 1.4f;
                        wantFov = 46f;
                        break;
                    }
                case MatchPhase.Corner:
                case MatchPhase.RoundEnd when m.phaseT > 1.2f:
                    {
                        // face close-up: injuries, sweat, breathing
                        var fwd = p.rig.head.forward.Flat().normalized;
                        if (fwd.sqrMagnitude < 0.01f) fwd = p.transform.forward;
                        wantPos = ph + fwd * 0.85f + Vector3.up * 0.04f + p.transform.right * 0.18f;
                        wantLook = ph + Vector3.up * 0.1f;
                        wantFov = 34f;
                        break;
                    }
                case MatchPhase.Knockdown when m.downed != null:
                    {
                        var dp = m.downed.rig.hips.position;
                        var side = Vector3.Cross(Vector3.up, (dp - center).Flat().normalized);
                        if (side.sqrMagnitude < 0.01f) side = Vector3.right;
                        wantPos = dp + side * 2.6f + Vector3.up * 0.55f - (dp - center).Flat().normalized * 0.6f;
                        wantLook = dp + Vector3.up * 0.25f;
                        wantFov = 48f;
                        break;
                    }
                case MatchPhase.KOSequence:
                case MatchPhase.Replay:
                    {
                        var loser = m.winner == p ? o : p;
                        var focus = loser.rig.hips.position;
                        float a = orbit * 1.6f;
                        float r = m.phase == MatchPhase.Replay ? 2.6f : 3.2f;
                        wantPos = focus + new Vector3(Mathf.Cos(a) * r, 0.7f, Mathf.Sin(a) * r);
                        wantLook = focus + Vector3.up * 0.35f;
                        wantFov = 44f;
                        break;
                    }
                case MatchPhase.Result:
                    {
                        var hero = m.winner != null ? m.winner : p;
                        var f = hero.transform.forward;
                        wantPos = hero.rig.head.position + f * 2.4f + Vector3.up * -0.35f + hero.transform.right * 0.6f;
                        wantLook = hero.rig.head.position + Vector3.up * 0.1f;
                        wantFov = 42f;
                        break;
                    }
                default:
                    {
                        var toOpp = (oh - ph).Flat();
                        float dist = Mathf.Max(0.3f, toOpp.magnitude);
                        var dir = toOpp / dist;
                        var right = Vector3.Cross(Vector3.up, dir);
                        if (m.broadcastCam)
                        {
                            var mid = (ph + oh) * 0.5f;
                            var side = right;
                            if (Vector3.Dot(side, (center - mid).Flat()) > 0f) side = -side; // shoot from the outside in
                            wantPos = mid - side * (3.4f + dist * 0.8f) + Vector3.up * 0.35f;
                            wantLook = mid + Vector3.down * 0.05f;
                            wantFov = 44f;
                        }
                        else
                        {
                            float back = Mathf.Lerp(1.75f, 2.4f, Mathf.InverseLerp(0.6f, 2.2f, dist));
                            wantPos = ph - dir * back + right * 0.55f + Vector3.up * 0.3f;
                            wantLook = Vector3.Lerp(ph, oh, 0.68f) + Vector3.down * 0.08f;
                            wantFov = Mathf.Lerp(48f, 56f, Mathf.InverseLerp(0.7f, 2.2f, dist));
                        }
                        break;
                    }
            }
            float posK = m.phase == MatchPhase.Fight ? 9f : 4f;
            if (!init) { pos = wantPos; rot = Quaternion.LookRotation(wantLook - wantPos); fov = wantFov; init = true; }
            pos = Vector3.Lerp(pos, wantPos, 1f - Mathf.Exp(-posK * dt));
            var wantRot = Quaternion.LookRotation((wantLook - pos).sqrMagnitude > 1e-4f ? wantLook - pos : Vector3.forward);
            rot = Quaternion.Slerp(rot, wantRot, 1f - Mathf.Exp(-11f * dt));
            fov = Mathf.Lerp(fov, wantFov, 1f - Mathf.Exp(-5f * dt));
            var offRot = Quaternion.Euler(CameraFX.RotationOffset);
            Cam.transform.SetPositionAndRotation(pos + rot * CameraFX.PositionOffset, rot * offRot);
            Cam.fieldOfView = fov + CameraFX.FovOffset;
        }
    }
}
