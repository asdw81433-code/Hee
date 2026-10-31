namespace NeonBay
{
    public static class Lore
    {
        public struct Entry { public string title, text; }

        static readonly Entry[] shards =
        {
            new Entry { title = "The Drowning (2045)", text = "When the Atlantic rose for the last time, old Miami didn't sink so much as surrender. Washington sent a FEMA trailer and a thoughts-and-prayers tweet. Everyone else moved up a floor. Neon Bay is the city they built on the roofs of the one that died." },
            new Entry { title = "Helix Dynamics - Prospectus", text = "\"Helix: Live Forever.\" Founded in 2051 to build hurricane barriers, Helix now owns the Megawall, the water, the power grid and forty percent of the NBPD's budget. Its board has not met in person since 2079. Some say it doesn't need to." },
            new Entry { title = "NBPD Precinct Memo #4471", text = "Officers are reminded that Helix-owned property takes priority over civilian complaints. Response times in Lowtown are 'aspirational'. Do not engage Burnouts without Riot Unit support. Do not, under any circumstances, eat the chili dogs in the evidence locker." },
            new Entry { title = "The Megawall", text = "Eighty-five meters of concrete and pumps hold back the ocean. Every resident pays the 'Wall Tax' through their water bill. Nobody has been allowed outside the Wall since the Quarantine of '74. Officially, there's nothing out there but water and hurricanes." },
            new Entry { title = "Chrome Jackals - Graffiti", text = "WE WERE THE KIDS UNDER THE OVERPASS. WE ATE YOUR TRASH AND LEARNED YOUR LOCKS. NOW WE WEAR YOUR CHROME. LOWTOWN IS OURS. - J" },
            new Entry { title = "Wet Lotus Syndicate", text = "The Lotus began as a longshoremen's union in Port Marrow. Today it runs half the Neon Strip, every nightclub worth dancing in and most of the city's smuggled implants. Madame Lotus has never been photographed. Every year she looks exactly the same." },
            new Entry { title = "Static Saints Manifesto", text = "Information wants to be free. So do people. Helix digitized the Flood Year protesters 'for preservation'. We say: show us the archive. Release the ghosts. We are the static between their channels." },
            new Entry { title = "June Alvarez (Flood Year Activist)", text = "June Alvarez, 24, organized the Flood Year water riots of 2061 and forced Helix to open the pumps for Lowtown. She died in NBPD custody. Helix claimed her body for 'neural research'. The file was sealed for 99 years." },
            new Entry { title = "Burnouts", text = "Too much chrome, too little humanity. When the nervous system rejects its own upgrades, the result is a Burnout: a person running on combat firmware and pain. The NBPD has a Riot Unit for that. It usually arrives late." },
            new Entry { title = "Strip Racing", text = "The Zip Trike was supposed to be a cheap delivery bike. Then somebody bolted a jet cooler to one and raced it down the Neon Strip at 3 AM. The record from Ocean Avenue to the Port is 1:12. Nobody knows who set it." },
            new Entry { title = "The Scar", text = "The south-east districts were 'reclaimed' in 2071 after the Helix reactor fire. Officially the fallout is gone. Unofficially, the Scar Raiders live there because nobody else will, and they strip anything that drives through." },
            new Entry { title = "Mama Sol's Ledger (page torn)", text = "Debts owed to me: half the Strip. Debts I owe: one, to a girl named June, from a long time ago. I was supposed to cut the alarms for her that night. I didn't. Forty pots of coffee a day for twenty years, and it still isn't paid." },
            new Entry { title = "Bay Metro - Service Notice", text = "Due to flooding, sabotage, hurricanes, unrest, or other acts of God and/or Static Saints, service may be interrupted. Helix reminds passengers that fare evasion is a crime of moral character." },
            new Entry { title = "Synapse+ Advertisement", text = "Why remember when you can recall? Synapse+ decks give you perfect memory, faster thoughts and 12 free months of Helix Cloud. Side effects may include: dreams that aren't yours." },
            new Entry { title = "Dutch's Workbench Notes", text = "Convoy autopilots run Helix firmware v9. Lazy. Backdoor on port 4096 if you've got the relay key. Note to self: stop helping people who get shot at." },
            new Entry { title = "Ghosts in the Net", text = "Netrunners swear there are things in the deep Net that think. Not AIs - something older, slower, human-shaped. They leave messages in dead billboards. They ask for their names back." },
            new Entry { title = "Hurricane Shrines", text = "Even on the 90th floor, people still keep a candle, a saint card and a bottle of rum by the window when a storm comes in. The Helix facilities manager tried to ban them once. The elevators stopped working for a week. Nobody tried again." },
            new Entry { title = "The Pit - Fight Card", text = "TONIGHT: IRON POLLY (undefeated, 41-0) vs ANY FOOL WITH A PULSE. No guns. No chrome sidearms. No refunds. Promoter Chaz not responsible for death, dismemberment or emotional growth." },
            new Entry { title = "Helix Internal - Project LOTUS", text = "Phase 3 complete: subject J. successfully compressed into portable lattice. Personality stable. Subject is... asking questions. Recommend transport to Spire uplink for integration into city management core. Subject's empathy may be useful. Or removable." },
            new Entry { title = "Unsent Message", text = "If you're reading this, I'm already in the wall. Not the Megawall - the walls of the Net. It's cold here, but I can see the whole city from inside the lights. Tell my mother I kept the pumps open. - J." },
        };

        public static Entry Shard(int i) => shards[((i % shards.Length) + shards.Length) % shards.Length];
        public static int ShardCount => shards.Length;

        public const string HomeTerminal =
            "[MAMA SOL] Wake up, little ghost. I have work that pays in real money, not promises. Sol's Diner, Neon Strip. Don't make me reheat the coffee.\n\n" +
            "[LANDLORD BOT] Rent for Mega-Block 7, Unit 1214 is overdue. Late fees are now sentient and have begun compounding.\n\n" +
            "[UNKNOWN SENDER] ...can you hear me? ...the lotus... is opening...";
    }
}
