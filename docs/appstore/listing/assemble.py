import sys, os, json
D = os.path.dirname(os.path.abspath(__file__))
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
P = {
 "IOS": dict(intro="intro_ios", core=["c_direct","c_library","c_search","c_playback","c_feeds","c_home","c_multi","c_sync","c_privacy"],
   plus_intro="plus_intro", h_inc="h_included", plus=["p_subs","p_motion","p_downloads","p_mini","p_verticals","p_tools","p_icons_ios"],
   new=["n_lang","n_foryou","n_forgotten","n_rows","n_dropdown","n_detail","n_local","n_landscape_ios","n_feeds_ios","n_groups","n_tasks_ios","n_skip","n_faster","n_fixes"]),
 "MAC_OS": dict(intro="intro_mac", core=["c_direct","c_library","c_search","c_playback","c_feeds","c_keyboard_mac","c_home","c_multi","c_sync","c_privacy"],
   plus_intro="plus_intro", h_inc="h_included", plus=["p_subs","p_motion","p_downloads","p_mini","p_verticals","p_tools"],
   new=["n_lang","n_foryou","n_forgotten","n_rows","n_dropdown","n_detail","n_local","n_feeds_mac","n_groups","n_skip","n_faster","n_fixes"]),
 "TV_OS": dict(intro="intro_tv", core=["c_direct_tv","c_library_tv","c_search_tv","c_playback_tv","c_markers_tv","c_ratings_tv","c_previews_tv","c_multi","c_pin_tv","c_privacy"],
   plus_intro="plus_intro_tv", h_inc="h_included_tv", plus=["p_channels_tv"],
   new=["n_lang","n_feeds_tv","n_local","n_lock_tv","n_fixes_tv"]),
}
LOCALES = ["en-US","de-DE","fr-FR","nl-NL","sv","da","no","pl","ja","pt-BR","zh-Hans","zh-Hant","ar-SA"]
def build(loc, plat):
    t = json.load(open(os.path.join(D, loc + ".json"))); p = P[plat]
    b = lambda ks: "\n".join("• " + t[k] for k in ks)
    desc = "\n\n".join([t[p["intro"]], t["h_core"] + "\n" + b(p["core"]), t["h_plus"] + "\n" + t[p["plus_intro"]],
        t[p["h_inc"]] + "\n" + b(p["plus"]) + "\n" + t["avail"], t["req"] + "\n" + t["eula"] + " " + EULA])
    new = b(p["new"])
    if plat == "MAC_OS" and loc == "en-US": new = new.replace("built on your device", "built on your Mac")
    return {"description": desc, "keywords": t["keywords"], "whatsNew": new}
if __name__ == "__main__":
    src = set(json.load(open(os.path.join(D, "en-US.json"))))
    for loc in LOCALES:
        f = os.path.join(D, loc + ".json")
        if not os.path.exists(f): print(loc, "MISSING"); continue
        t = json.load(open(f)); 
        print(loc, "keys ok" if set(t) == src else ("DIFF", set(t) ^ src), "kw", len(t["keywords"]), [len(build(loc, pl)["description"]) for pl in P])
