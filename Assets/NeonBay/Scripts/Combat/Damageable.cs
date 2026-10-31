using System;
using UnityEngine;

namespace NeonBay
{
    public enum DamageType { Ballistic, Melee, Explosive, Electric, Fall, Vehicle, Hack, Fire }

    public struct DamageInfo
    {
        public float amount;
        public DamageType type;
        public Vector3 point;
        public Vector3 direction;
        public GameObject source;
        public bool headshot;
        public bool crit;
        public bool fromPlayer;
        public float force;
        public bool stealth;
    }

    /// <summary>Marks a collider as a body part. Headshots multiply damage.</summary>
    public class Hitbox : MonoBehaviour
    {
        public Damageable owner;
        public float multiplier = 1f;
        public bool head;
    }

    /// <summary>Health + armor for anything that can be hurt (player, NPCs, vehicles, drones, devices).</summary>
    public class Damageable : MonoBehaviour
    {
        public float maxHealth = 100f;
        public float health = 100f;
        public float armor;               // flat damage reduction percentage scale (0..100+)
        public bool invulnerable;
        public bool isDead;
        public FactionId faction = FactionId.Civilian;
        public bool isRobotic;
        public float lastDamageTime = -99f;
        public GameObject lastAttacker;

        /// <summary>Optional hook that can modify incoming damage before armor (blocking, perks, difficulty).</summary>
        public Func<DamageInfo, DamageInfo> filter;
        public event Action<DamageInfo> Damaged;
        public event Action<DamageInfo> Died;

        public float Fraction => maxHealth > 0 ? Mathf.Clamp01(health / maxHealth) : 0f;

        public void Init(float hp, float arm = 0f)
        {
            maxHealth = hp; health = hp; armor = arm; isDead = false;
        }

        public virtual void ApplyDamage(DamageInfo info)
        {
            if (isDead || invulnerable) return;
            if (filter != null) info = filter(info);
            float amount = info.amount;
            if (amount <= 0f) return;
            if (info.type != DamageType.Hack && info.type != DamageType.Fall)
                amount *= 100f / (100f + Mathf.Max(0f, armor));
            if (isRobotic && info.type == DamageType.Electric) amount *= 2f;
            info.amount = amount;
            health -= amount;
            lastDamageTime = Time.time;
            lastAttacker = info.source;
            Damaged?.Invoke(info);
            if (health <= 0f)
            {
                health = 0f;
                isDead = true;
                Died?.Invoke(info);
            }
        }

        public void Heal(float amount)
        {
            if (isDead) return;
            health = Mathf.Min(maxHealth, health + amount);
        }

        public void Revive(float fraction = 1f)
        {
            isDead = false;
            health = maxHealth * fraction;
        }

        /// <summary>Resolves the damageable and multiplier for a collider that was hit.</summary>
        public static Damageable Resolve(Collider c, out float multiplier, out bool head)
        {
            multiplier = 1f; head = false;
            if (c == null) return null;
            var hb = c.GetComponent<Hitbox>();
            if (hb != null && hb.owner != null)
            {
                multiplier = hb.multiplier; head = hb.head;
                return hb.owner;
            }
            return c.GetComponentInParent<Damageable>();
        }
    }
}
