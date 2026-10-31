using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    /// <summary>Anything the player can use with the interact key or affect with a device hack.</summary>
    public abstract class Interactable : MonoBehaviour
    {
        public string id;
        public string prompt = "Use";
        public bool usable = true;
        public float range = 2.8f;

        public virtual string Prompt => prompt;
        public virtual bool CanInteract => usable;
        public abstract void Interact();

        // Device hacking (through the scanner)
        public virtual bool Hackable => false;
        public virtual string HackLabel => "Hack";
        public virtual int HackCost => 1;
        public virtual void OnHacked() { }

        protected void Raise() => GameEvents.RaiseInteracted(id);

        public static T Create<T>(string name, Transform parent, Vector3 pos, Vector3 boxSize, Vector3 facing, int layer = Layers.World) where T : Interactable
        {
            var go = new GameObject(name) { layer = layer };
            go.transform.SetParent(parent, false);
            go.transform.position = pos;
            if (facing.sqrMagnitude > 0.01f) go.transform.rotation = Quaternion.LookRotation(facing.Flat().normalized);
            var col = go.AddComponent<BoxCollider>();
            col.size = boxSize;
            col.center = new Vector3(0, boxSize.y * 0.5f, 0);
            return go.AddComponent<T>();
        }
    }

    public class Teleporter : Interactable
    {
        public Vector3 target;
        public float targetYaw;
        public string requiredFlag;
        public string lockedText = "Locked";

        public override string Prompt => !string.IsNullOrEmpty(requiredFlag) && !Flags.Has(requiredFlag) ? lockedText : prompt;
        public override bool CanInteract => usable && (string.IsNullOrEmpty(requiredFlag) || Flags.Has(requiredFlag));

        public override void Interact()
        {
            if (Game.Player == null) return;
            Game.Audio?.Play2D("door", 0.8f);
            Game.UI?.Fade(0.35f);
            Game.Player.Teleport(target, targetYaw);
            Raise();
        }
    }

    public class ShopPoint : Interactable
    {
        public string shopId;
        public string shopName;
        public override void Interact()
        {
            Game.UI?.OpenShop(shopId, shopName);
            Raise();
        }
    }

    public class VendingMachine : Interactable
    {
        public int price = 15;
        public string itemId = "volt_cola";
        bool hacked;
        public override string Prompt => $"Buy {Items.Get(itemId)?.name} (${price})";
        public override void Interact()
        {
            if (Game.Stats == null) return;
            if (!Game.Stats.Spend(price)) { Game.UI?.Notify("Not enough credits", Palette.Red); Game.Audio?.Play2D("ui_error"); return; }
            Game.Inventory.Add(itemId, 1);
            Game.Audio?.Play3D("vend", transform.position, 0.9f);
        }
        public override bool Hackable => !hacked;
        public override string HackLabel => "Jackpot (free drinks)";
        public override void OnHacked()
        {
            hacked = true;
            Game.Inventory.Add(itemId, 3);
            Game.Audio?.Play3D("vend", transform.position, 1f);
            Game.UI?.Notify("Vending machine spat out 3 drinks", Palette.Cyan);
        }
    }

    public class Atm : Interactable
    {
        bool drained;
        public override string Prompt => "Check balance";
        public override void Interact()
        {
            Game.UI?.Notify("Balance: " + Util.Credits(Game.Stats != null ? Game.Stats.Money : 0), Palette.Cyan);
            Game.Audio?.Play2D("ui_blip");
        }
        public override bool Hackable => !drained;
        public override string HackLabel => "Drain account";
        public override int HackCost => 2;
        public override void OnHacked()
        {
            drained = true;
            int amount = Random.Range(120, 420) + (Game.Stats != null ? Game.Stats.Level * 25 : 0);
            Game.Stats?.AddMoney(amount);
            Game.UI?.Notify("+" + Util.Credits(amount) + " siphoned", Palette.Green);
            GameEvents.RaiseCrime(CrimeType.Hacking, transform.position);
            Game.Audio?.Play3D("cash", transform.position);
        }
    }

    public class Bed : Interactable
    {
        public override string Prompt => "Sleep / Save";
        public override void Interact() { Game.UI?.OpenSleep(); Raise(); }
    }

    public class MetroGate : Interactable
    {
        public Location location;
        public override string Prompt => "Metro - fast travel";
        public override void Interact()
        {
            if (location != null && !location.discovered)
            {
                location.discovered = true;
                Game.UI?.Notify("Metro station discovered: " + location.name, Palette.Cyan);
            }
            Game.UI?.OpenMetro(location);
        }
    }

    public class DataShard : Interactable
    {
        public int index;
        public override string Prompt => "Read data shard";
        void Update() => transform.Rotate(Vector3.up, 60f * Time.deltaTime, Space.World);
        public override void Interact()
        {
            Flags.Set("shard_" + index);
            var lore = Lore.Shard(index);
            Game.UI?.ShowLore(lore.title, lore.text);
            Game.Stats?.AddXP(60);
            Game.Audio?.Play2D("pickup");
            gameObject.SetActive(false);
        }
    }

    /// <summary>Generic object that a quest listens for (case to grab, panel to press...).</summary>
    public class QuestObject : Interactable
    {
        public bool disableOnUse = true;
        public string requiredFlag;
        public override bool CanInteract => usable && (string.IsNullOrEmpty(requiredFlag) || Flags.Has(requiredFlag));
        public override void Interact()
        {
            Game.Audio?.Play2D("ui_confirm");
            Raise();
            if (disableOnUse) usable = false;
        }
    }

    /// <summary>A terminal that can be hacked (mission objective) or simply read.</summary>
    public class Terminal : Interactable
    {
        public string hackId;
        public string readTitle, readText;
        public bool hacked;
        public bool requireHack = true;
        public int cost = 1;

        public override string Prompt => requireHack ? (hacked ? "Terminal (offline)" : "Hack terminal [scanner]") : "Read terminal";
        public override void Interact()
        {
            if (!requireHack && !string.IsNullOrEmpty(readText)) { Game.UI?.ShowLore(readTitle, readText); Raise(); return; }
            if (requireHack && !hacked)
            {
                // manual breach takes a moment but needs no RAM
                Game.Hacking?.StartManualBreach(this);
            }
        }
        public override bool Hackable => requireHack && !hacked;
        public override string HackLabel => "Breach terminal";
        public override int HackCost => cost;
        public override void OnHacked()
        {
            hacked = true;
            Game.Audio?.Play3D("hack_done", transform.position);
            GameEvents.RaiseHackCompleted(hackId);
        }
    }

    public class LootCrate : Interactable
    {
        public int tier = 1;
        public bool opened;
        public string questId;
        public override string Prompt => opened ? "Empty" : "Open crate";
        public override bool CanInteract => !opened;
        public override void Interact()
        {
            opened = true;
            Loot.RollCrate(tier, transform.position);
            Game.Audio?.Play3D("crate", transform.position);
            Raise();
            var lid = transform.Find("Lid");
            if (lid != null) lid.localRotation = Quaternion.Euler(-70, 0, 0);
        }
    }

    public class Pickup : Interactable
    {
        public string itemId;
        public int count = 1;
        public int money;
        public WeaponInstance weapon;
        float bob;

        public override string Prompt
        {
            get
            {
                if (weapon != null) return "Take " + weapon.DisplayName;
                if (money > 0 && string.IsNullOrEmpty(itemId)) return "Take " + Util.Credits(money);
                var it = Items.Get(itemId);
                return "Take " + (it != null ? it.name : itemId) + (count > 1 ? " x" + count : "");
            }
        }

        void Update()
        {
            bob += Time.deltaTime;
            transform.Rotate(Vector3.up, 45f * Time.deltaTime, Space.World);
            // auto pick up ammo and money when walked over
            if (Game.Player != null && weapon == null && (Game.PlayerPos - transform.position).sqrMagnitude < 1.6f)
            {
                var it = Items.Get(itemId);
                if (money > 0 || (it != null && it.kind == ItemKind.Ammo)) Interact();
            }
        }

        public override void Interact()
        {
            if (money > 0) Game.Stats?.AddMoney(money);
            if (!string.IsNullOrEmpty(itemId)) Game.Inventory?.Add(itemId, count);
            if (weapon != null) Game.Inventory?.AddWeapon(weapon, true);
            Game.Audio?.Play2D("pickup", 0.7f);
            Destroy(gameObject);
        }

        public static Pickup Spawn(Vector3 pos, string itemId, int count, int money = 0, WeaponInstance weapon = null)
        {
            var go = new GameObject("Pickup") { layer = Layers.Triggers };
            go.transform.position = pos + Vector3.up * 0.35f;
            var col = go.AddComponent<SphereCollider>();
            col.radius = 0.45f;
            col.isTrigger = true;
            var p = go.AddComponent<Pickup>();
            p.itemId = itemId; p.count = count; p.money = money; p.weapon = weapon;
            Color c = weapon != null ? weapon.RarityColor : money > 0 ? Palette.Green : Palette.Cyan;
            var vis = Util.Primitive(PrimitiveType.Cube, "Vis", go.transform, Vector3.zero, weapon != null ? new Vector3(0.6f, 0.15f, 0.2f) : Vector3.one * 0.22f,
                Mats.Cached("pickup" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Unlit(c * 3f)));
            vis.layer = Layers.Triggers;
            var glow = Util.Primitive(PrimitiveType.Quad, "Glow", go.transform, Vector3.zero, Vector3.one * 0.9f,
                Mats.Cached("pickupglow" + ColorUtility.ToHtmlStringRGB(c), () => Mats.Additive(c.WithAlpha(0.6f), Tex.Glow)));
            glow.AddComponent<Billboard>();
            glow.layer = Layers.Triggers;
            Destroy(go, 240f);
            return p;
        }
    }

    public class RaceStart : Interactable
    {
        public string raceId;
        public override string Prompt => "Start race: " + (Game.City.Loc(raceId)?.name ?? raceId) + (Game.Player != null && Game.Player.InVehicle ? "" : " (need a vehicle)");
        public override bool CanInteract => true;
        public override void Interact() { Game.Activities?.StartRace(raceId); }
        void Update()
        {
            // drivers can start by stopping inside the marker and honking/pressing E from the car
            if (Game.Player != null && Game.Player.InVehicle && (Game.PlayerPos - transform.position).Flat().sqrMagnitude < 36f && InputHub.Down(Btn.Interact))
                Interact();
        }
    }

    public class Billboard : MonoBehaviour
    {
        void LateUpdate()
        {
            var c = Game.Cam;
            if (c != null) transform.rotation = Quaternion.LookRotation(transform.position - c.transform.position);
        }
    }
}
