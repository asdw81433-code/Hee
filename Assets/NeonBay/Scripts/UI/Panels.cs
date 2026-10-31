using System;
using System.Collections.Generic;
using UnityEngine;

namespace NeonBay
{
    public partial class UIManager
    {
        class ShopEntry { public string label, desc; public int price; public Func<bool> can; public Action buy; public Color color = Color.white; }
        string shopId, shopTitle;
        int shopTab; // 0 buy, 1 sell, 2 upgrade
        string loreTitle, loreText;
        string gigFixer;
        List<GigOffer> gigOffers;

        // ================================================================== openers (called by gameplay)
        public void OpenShop(string id, string title)
        {
            shopId = id; shopTitle = title; shopTab = id == "fence" ? 1 : 0;
            OpenModal(Modal.Shop);
        }

        public void OpenSleep() => OpenModal(Modal.Sleep);
        public void OpenMetro(Location from) => OpenModal(Modal.Metro);
        public void OpenGarage() => OpenModal(Modal.Garage);

        public void ShowLore(string title, string text)
        {
            loreTitle = title; loreText = text;
            if (Game.Manager.State == GameState.Paused) { modal = Modal.Lore; return; }
            OpenModal(Modal.Lore);
        }

        void CloseLore()
        {
            bool fromPause = Game.Manager.State == GameState.Paused;
            modal = Modal.None;
            modalClosedFrame = Time.frameCount;
            if (!fromPause && Game.Manager.State == GameState.Shop) Game.Manager.SetState(GameState.Playing);
        }

        public void OpenGigBoard(string fixer, List<GigOffer> offers)
        {
            gigFixer = fixer; gigOffers = offers;
            OpenModal(Modal.Gigs);
        }

        Rect Window(float w, float h, string title)
        {
            var r = new Rect(W * 0.5f - w * 0.5f, H * 0.5f - h * 0.5f, w, h);
            UISkin.Rect(new Rect(0, 0, W, H), new Color(0, 0, 0, 0.45f));
            GUI.Box(r, GUIContent.none, UISkin.panel);
            UISkin.Text(new Rect(r.x + 24, r.y + 14, w - 48, 34), title, UISkin.header, UISkin.Accent);
            if (UISkin.Button(new Rect(r.xMax - 140, r.y + 12, 120, 38), "CLOSE [ESC]")) { if (modal == Modal.Lore) CloseLore(); else CloseModal(); }
            return new Rect(r.x + 24, r.y + 60, w - 48, h - 80);
        }

        // ================================================================== shop
        int Price(int basePrice) => Mathf.Max(1, Mathf.RoundToInt(basePrice * (Game.Stats != null ? Game.Stats.PriceMult : 1f)));

        List<ShopEntry> BuyList()
        {
            var l = new List<ShopEntry>();
            var s = Game.Stats; var inv = Game.Inventory;
            void Item(string id, int count, int price)
            {
                var d = Items.Get(id);
                int p = Price(price);
                l.Add(new ShopEntry { label = d.name + (count > 1 ? " x" + count : ""), desc = d.desc, price = p, can = () => s.Money >= p, buy = () => { if (s.Spend(p)) inv.Add(id, count); } });
            }
            switch (shopId)
            {
                case "guns":
                    foreach (var w in Weapons.All)
                    {
                        if (w.cls == WeaponClass.Fists) continue;
                        var def = w;
                        int tier = s.StreetCred >= 120 ? 2 : s.StreetCred >= 40 ? 1 : 0;
                        int p = Price(Mathf.RoundToInt(def.price * (1f + tier * 0.6f)));
                        l.Add(new ShopEntry { label = def.name + "  [" + Weapons.RarityName(tier) + "]", desc = def.desc, price = p, color = Weapons.RarityColor(tier), can = () => s.Money >= p, buy = () => { if (s.Spend(p)) inv.AddWeapon(new WeaponInstance(def.id, tier), true); } });
                    }
                    Item("ammo_light", 40, 70); Item("ammo_rifle", 40, 110); Item("ammo_shells", 16, 70); Item("ammo_heavy", 12, 90);
                    Item("frag", 1, 130); Item("emp", 1, 160);
                    break;
                case "net":
                    foreach (var q in Hacking.All)
                    {
                        if (q.price <= 0 || s.quickhacks.Contains(q.id)) continue;
                        var qq = q; int p = Price(q.price);
                        l.Add(new ShopEntry { label = "Quickhack: " + q.name + "  (" + q.cost + " RAM)", desc = q.desc, price = p, color = Palette.Cyan, can = () => s.Money >= p, buy = () => { if (s.Spend(p)) { s.quickhacks.Add(qq.id); Notify("Quickhack installed: " + qq.name, Palette.Cyan); } } });
                    }
                    Item("ram_shot", 1, 110); Item("stim", 1, 160);
                    break;
                case "clinic":
                    foreach (var c in CyberwareDB.All)
                    {
                        if (s.HasCyber(c.id)) continue;
                        var cd = c;
                        int p = Price(Mathf.RoundToInt(c.price * (Flags.Has("doc_discount") ? 0.85f : 1f)));
                        var installed = s.InSlot(c.slot);
                        l.Add(new ShopEntry
                        {
                            label = c.name + "  <size=13>[" + c.slot + (c.level > 1 ? ", LV " + c.level : "") + "]</size>",
                            desc = c.desc + (installed != null ? "  (replaces " + installed.name + ")" : ""),
                            price = p, color = Palette.Cyan,
                            can = () => s.Money >= p && s.Level >= cd.level,
                            buy = () => { if (s.Spend(p)) { s.Install(cd); Notify("Installed " + cd.name, Palette.Cyan); Game.Audio?.Play2D("hack_done", 0.5f); } }
                        });
                    }
                    Item("medkit", 1, 120); Item("stim", 1, 160);
                    break;
                case "cars":
                    foreach (var (t, price) in new[] { (VehicleType.Trike, 3500), (VehicleType.Taxi, 7000), (VehicleType.Sedan, 9000), (VehicleType.Van, 12000), (VehicleType.Muscle, 16000), (VehicleType.Sports, 32000) })
                    {
                        var vt = t; int p = Price(price);
                        bool owned = Game.Traffic.owned.Contains(vt.ToString());
                        l.Add(new ShopEntry { label = Vehicle.TypeName(vt) + (owned ? "  (owned)" : ""), desc = "Delivered to you anywhere with [T].", price = owned ? 0 : p, can = () => !owned && s.Money >= p, buy = () => { if (s.Spend(p)) { Game.Traffic.Own(vt.ToString()); Notify("Bought " + Vehicle.TypeName(vt) + " - press [T] to call it", Palette.Yellow); } } });
                    }
                    break;
                case "bar":
                    Item("synth_beer", 1, 20); Item("volt_cola", 1, 15); Item("gumbo", 1, 55); Item("street_food", 1, 30);
                    break;
                case "food":
                    Item("street_food", 1, 30); Item("noodle_cup", 1, 15); Item("gumbo", 1, 55); Item("volt_cola", 1, 15);
                    break;
            }
            return l;
        }

        List<ShopEntry> SellList()
        {
            var l = new List<ShopEntry>();
            var s = Game.Stats; var inv = Game.Inventory;
            foreach (var kv in new List<KeyValuePair<string, int>>(inv.AllItems))
            {
                var d = Items.Get(kv.Key);
                if (d == null || d.kind == ItemKind.Quest || d.kind == ItemKind.Ammo) continue;
                if (d.kind != ItemKind.Junk && d.kind != ItemKind.Component && shopId == "fence") { }
                int p = Mathf.Max(1, Mathf.RoundToInt(d.price * (d.kind == ItemKind.Junk ? 1f : 0.4f)));
                var id = kv.Key;
                l.Add(new ShopEntry { label = d.name + " x" + kv.Value, desc = d.desc, price = p, can = () => inv.Has(id), buy = () => { if (inv.Remove(id)) s.AddMoney(p); } });
            }
            foreach (var w in inv.weapons.ToArray())
            {
                if (Array.IndexOf(inv.slots, w) >= 0) continue;
                var ww = w;
                l.Add(new ShopEntry { label = w.DisplayName + "  [" + Weapons.RarityName(w.tier) + "]", desc = "Unequipped weapon", price = w.SellValue, color = w.RarityColor, can = () => true, buy = () => { inv.RemoveWeapon(ww); s.AddMoney(ww.SellValue); } });
            }
            return l;
        }

        List<ShopEntry> UpgradeList()
        {
            var l = new List<ShopEntry>();
            var s = Game.Stats; var inv = Game.Inventory;
            foreach (var w in inv.weapons)
            {
                if (w.Def == null || w.mod >= 5) continue;
                var ww = w;
                int scrap = Mathf.CeilToInt(w.UpgradeScrap * (s.HasPerk("tinkerer") ? 0.7f : 1f));
                int p = Price(w.UpgradeCost);
                l.Add(new ShopEntry { label = w.DisplayName + "  ->  +" + (w.mod + 1), desc = "+8% damage. Needs " + scrap + " Tech Scrap (you have " + inv.Count("scrap") + ").", price = p, color = w.RarityColor, can = () => s.Money >= p && inv.Count("scrap") >= scrap, buy = () => { if (s.Spend(p) && inv.Remove("scrap", scrap)) { ww.mod++; Notify(ww.DisplayName + " upgraded", Palette.Green); Game.Weapons.OnLoadoutChanged(); } } });
            }
            return l;
        }

        void DrawShop()
        {
            var area = Window(980, 760, shopTitle?.ToUpperInvariant() ?? "SHOP");
            var s = Game.Stats;
            bool canSell = shopId != "cars";
            bool canUpgrade = shopId == "guns";
            float x = area.x;
            if (shopId != "fence" && UISkin.Button(new Rect(x, area.y, 150, 38), "BUY", shopTab == 0)) { shopTab = 0; scroll = Vector2.zero; }
            if (canSell && UISkin.Button(new Rect(x + 160, area.y, 150, 38), "SELL", shopTab == 1)) { shopTab = 1; scroll = Vector2.zero; }
            if (canUpgrade && UISkin.Button(new Rect(x + 320, area.y, 150, 38), "UPGRADE", shopTab == 2)) { shopTab = 2; scroll = Vector2.zero; }
            UISkin.Text(new Rect(area.xMax - 300, area.y + 6, 300, 30), Util.Credits(s.Money) + "   SCRAP " + Game.Inventory.Count("scrap"), UISkin.right, Palette.Green);
            var list = shopTab == 0 ? BuyList() : shopTab == 1 ? SellList() : UpgradeList();
            GUILayout.BeginArea(new Rect(area.x, area.y + 50, area.width, area.height - 50));
            scroll = GUILayout.BeginScrollView(scroll);
            if (list.Count == 0) GUILayout.Label("Nothing here.", UISkin.labelSmall);
            foreach (var e in list)
            {
                GUILayout.BeginHorizontal(UISkin.box);
                GUILayout.Label("<b><color=#" + ColorUtility.ToHtmlStringRGB(e.color) + ">" + e.label + "</color></b>\n<size=14>" + e.desc + "</size>", UISkin.labelSmall, GUILayout.Width(area.width - 230));
                GUI.enabled = e.can == null || e.can();
                if (GUILayout.Button((shopTab == 1 ? "SELL " : "") + (e.price > 0 ? Util.Credits(e.price) : "-"), UISkin.button, GUILayout.Width(170), GUILayout.Height(48)))
                {
                    e.buy?.Invoke();
                    Game.Audio?.Play2D(shopTab == 1 ? "cash" : "ui_confirm", 0.5f);
                }
                GUI.enabled = true;
                GUILayout.EndHorizontal();
            }
            GUILayout.EndScrollView();
            GUILayout.EndArea();
        }

        // ================================================================== gig board
        void DrawGigs()
        {
            string title = gigFixer == "police_hq" ? "NBPD BOUNTY BOARD" : "GIGS  //  " + (Game.City.Loc(gigFixer)?.name ?? gigFixer);
            var area = Window(920, 640, title);
            GUILayout.BeginArea(area);
            if (gigOffers == null || gigOffers.Count == 0) GUILayout.Label("No work today. Come back tomorrow.", UISkin.label);
            else
                foreach (var o in gigOffers)
                {
                    GUILayout.BeginHorizontal(UISkin.box);
                    GUILayout.Label("<b>" + o.title + "</b>   <color=#8899aa>LV " + o.level + "</color>\n<size=15>" + o.desc + "</size>", UISkin.label, GUILayout.Width(area.width - 230));
                    if (GUILayout.Button("ACCEPT\n" + Util.Credits(o.reward), UISkin.button, GUILayout.Width(180), GUILayout.Height(64)))
                    {
                        CloseModal();
                        Game.Activities.AcceptGig(o);
                    }
                    GUILayout.EndHorizontal();
                }
            GUILayout.EndArea();
        }

        // ================================================================== sleep
        void DrawSleep()
        {
            var area = Window(640, 460, "BED  //  " + Util.TimeString(Game.Env.timeOfDay) + "  DAY " + Game.Env.day);
            GUILayout.BeginArea(area);
            GUILayout.Label("Sleeping restores your health, clears status effects and saves the game.", UISkin.labelSmall);
            GUILayout.Space(10);
            void SleepFor(float h)
            {
                Game.Env.SkipHours(h);
                Game.Stats.HealFraction(1f);
                Game.Stats.ClearBuffs();
                Game.Stats.ram = Game.Stats.MaxRam;
                CloseModal();
                Fade(1.2f);
                Game.Manager.AutoSave();
                Notify("Slept " + h.ToString("0") + "h. It's " + Util.TimeString(Game.Env.timeOfDay) + ".", Palette.Cyan);
            }
            foreach (var h in new[] { 2f, 4f, 8f })
                if (GUILayout.Button("Sleep " + h + " hours", UISkin.button, GUILayout.Height(46))) SleepFor(h);
            float toMorning = Mathf.Repeat(8f - Game.Env.timeOfDay, 24f);
            float toNight = Mathf.Repeat(21f - Game.Env.timeOfDay, 24f);
            if (GUILayout.Button("Sleep until morning (08:00)", UISkin.button, GUILayout.Height(46))) SleepFor(Mathf.Max(0.5f, toMorning));
            if (GUILayout.Button("Sleep until night (21:00)", UISkin.button, GUILayout.Height(46))) SleepFor(Mathf.Max(0.5f, toNight));
            if (GUILayout.Button("Just save", UISkin.button, GUILayout.Height(46))) { if (Game.Manager.SaveTo(SaveSystem.Slots[0])) Notify("Saved to slot 1", Palette.Green); CloseModal(); }
            GUILayout.EndArea();
        }

        // ================================================================== metro
        void DrawMetro()
        {
            var area = Window(700, 620, "BAY METRO  //  FAST TRAVEL");
            GUILayout.BeginArea(area);
            GUILayout.Label("Travel to any station you have discovered.", UISkin.labelSmall);
            int count = 0;
            foreach (var l in Game.City.locations.Values)
            {
                if (l.type != LocType.Metro) continue;
                count++;
                GUI.enabled = l.discovered;
                if (GUILayout.Button(l.name + (l.discovered ? "" : "  (undiscovered)"), UISkin.button, GUILayout.Height(46)))
                {
                    CloseModal();
                    Game.Activities.FastTravel(l);
                }
                GUI.enabled = true;
            }
            GUILayout.EndArea();
        }

        // ================================================================== garage
        void DrawGarage()
        {
            var area = Window(640, 480, "YOUR VEHICLES");
            GUILayout.BeginArea(area);
            foreach (var v in Game.Traffic.owned)
            {
                if (!Enum.TryParse(v, out VehicleType t)) continue;
                if (GUILayout.Button("Call " + Vehicle.TypeName(t), UISkin.button, GUILayout.Height(50))) { CloseModal(); Game.Traffic.Summon(v); }
            }
            GUILayout.EndArea();
        }

        // ================================================================== lore popup
        void DrawLore()
        {
            var area = Window(820, 560, loreTitle ?? "");
            GUILayout.BeginArea(area);
            GUILayout.Label(loreText ?? "", new GUIStyle(UISkin.label) { fontSize = 19 });
            GUILayout.EndArea();
        }

        // ================================================================== dialogue
        void DrawDialogue()
        {
            var ds = Game.Dialogue;
            if (ds == null || ds.Node == null) return;
            UISkin.Rect(new Rect(0, 0, W, 70), Color.black);
            UISkin.Rect(new Rect(0, H - 70, W, 70), Color.black);
            var r = new Rect(W * 0.5f - 640, H - 400, 1280, 320);
            UISkin.Rect(r, new Color(0, 0, 0, 0.6f));
            UISkin.Rect(new Rect(r.x, r.y, 6, r.height), UISkin.Accent2);
            var node = ds.Node;
            var speakerCol = node.speaker == "JUNE" ? Palette.Cyan : Palette.Yellow;
            UISkin.Text(new Rect(r.x + 30, r.y + 16, 800, 30), node.speaker, UISkin.header, speakerCol);
            string text = node.text ?? "";
            int chars = Mathf.Clamp(Mathf.CeilToInt(text.Length * ds.typeProgress), 0, text.Length);
            UISkin.Text(new Rect(r.x + 30, r.y + 56, r.width - 60, 110), text.Substring(0, chars), new GUIStyle(UISkin.label) { fontSize = 21 }, Color.white);
            var choices = ds.VisibleChoices();
            float y = r.y + 170;
            if (ds.typeProgress >= 1f && choices.Count > 0)
            {
                for (int i = 0; i < choices.Count; i++)
                {
                    var c = choices[i];
                    bool ok = c.IsEnabled;
                    string tag = string.IsNullOrEmpty(c.tag) ? "" : (ok ? "<color=#ffd633>" : "<color=#665555>") + c.tag + "</color> ";
                    var br = new Rect(r.x + 30, y, r.width - 60, 34);
                    var label = (i + 1) + ".  " + tag + (ok ? c.text : "<color=#777777>" + c.text + "</color>");
                    if (GUI.Button(br, label, UISkin.button)) { ds.Choose(c); break; }
                    y += 38;
                    var ev = Event.current;
                    if (ev.type == EventType.KeyDown && (ev.keyCode == KeyCode.Alpha1 + i || ev.keyCode == KeyCode.Keypad1 + i)) { ev.Use(); ds.Choose(c); break; }
                }
            }
            else
            {
                if (UISkin.Button(new Rect(r.xMax - 260, r.yMax - 56, 230, 42), ds.typeProgress < 1f ? "..." : "CONTINUE  [SPACE]")) ds.Continue();
                if (Event.current.type == EventType.KeyDown && (Event.current.keyCode == KeyCode.Space || Event.current.keyCode == KeyCode.Return)) { ds.Continue(); Event.current.Use(); }
            }
        }
    }
}
