## Requirements

- **WoW Forever** (Interface 16001). The addons also list the retail interface versions, but they are only tested on WoW Forever.
- **EllesmereUI 9.4**, which has to be installed separately. The addons in this repository do **not** include it.

## Installation

1. Download this repository (**Code → Download ZIP**) and unzip it.
2. Copy the addon folders into `World of Warcraft\_classic_beta_\Interface\AddOns\`:
   - `EllesmereUIDworak` (**always needed**)
   - `EllesmereUITalents`
3. Restart the game completely. `/reload` is not enough for new addons.
4. In the AddOns list on the character screen, make sure **EllesmereUI Dworak** and the modules you want are enabled.

## Where to find the settings

Open the **EllesmereUI** settings panel. The **Dworak** section sits at the top of the sidebar:

```
Dworak  
  Talents
```

To move the on-screen elements, open EllesmereUI **Unlock Mode**. They are listed under the **Talent Reminder**.

---

## Talents

The reminder appears while you have talent points left to spend, and disappears once they are all spent.

**Settings:** EllesmereUI panel → **Dworak → Talents**, or type `/euitalents`.

| Setting | What it does |
|---|---|
| Unspent Talent Points Reminder | Turns the reminder on or off (off by default). |
| Sound | A sound that plays when the reminder appears, and again when you gain a new talent point. You can pick any EllesmereUI alert sound or SharedMedia sound. Default: None. |
| Font | The EUI Global Font, Blizzard Default, any EllesmereUI font, or a SharedMedia font. |
| Text Size | 8 to 72. |
| Background | Background opacity (0 = no background) and its color. |
| Label Color | **UI Accent Color** (follows EllesmereUI Global Settings, live) or **Custom** (pick any color). The number stays white. |
- The "Unspent Talent Points :" label uses the **UI Accent Color** (EllesmereUI Global Settings) and updates live when you change it. The number is white.
- If the count looks wrong, type `/euitalents debug` and include the chat output in your bug report.

- A live preview at the top of the settings page shows every change as you make it.
  
## Notes

- Settings are saved per EllesmereUI profile and follow profile switches.
- These addons use EllesmereUI's official Plugin API (`EllesmereUI\PLUGINS_API.md`), so EllesmereUI updates do not overwrite them.

## Author

inspi_ration
