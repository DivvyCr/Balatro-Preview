<h1 align="center">Divvy's Preview for Balatro</h1>

<div align="center">

![Version](https://img.shields.io/badge/latest-v3.2-blue.svg)
![GitHub License](https://img.shields.io/github/license/DivvyCR/Balatro-Preview?color=blue)

</div>

<p align="center"><img src="gifs/DVPreview_Demo-1.gif" style="width:100%" /></p>

<p align="center">
<b>Simulate the score and the dollars that you will get by playing the selected cards!</b>
</p>

## :point_right: Installation

 0. Install [Lovely](https://github.com/ethangreen-dev/lovely-injector)<br>
   Do you have Steamodded? Then, you probably already have Lovely!
 1. Download the latest release of this mod, [here](https://github.com/DivvyCr/Balatro-Preview/releases/latest).
 2. Unzip the downloaded folder to `C:\Users\[USER]\AppData\Roaming\Balatro\Mods`<br>
   You should have:<br>
   `...\Balatro\Mods\DVPreview`<br>
   `...\Balatro\Mods\DVSimulate`<br>
   `...\Balatro\Mods\DVSettings`<br>
 3. Launch the game!

## :point_right: Features

 - Score and dollar preview **without side-effects**!
 - **Updates in real-time** when changing selected cards, changing joker order, or using consumables!
 - Can preview score even when cards are face-down!
 - Perfectly **predicts random effects**...
 - ... or not! There is an option to show the **minimum and maximum possible scores** when probabilities are involved!

> [!NOTE]
> **Accurate Mode** (on by default) previews modded jokers, cards, consumables and blinds without any
> per-mod support code. See the *Accurate Mode* section below. The original hand-written simulation is
> still used as a fallback.

## :point_right: See It In Action

<p align="center"><img src="gifs/DVPreview_Demo-2.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview updating in real-time.</p>

&nbsp;

<p align="center"><img src="gifs/DVPreview_Demo-3.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview being hidden with face-down cards.</p>

&nbsp;

<p align="center"><img src="gifs/DVPreview_Demo-4.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview updating in real-time, pay attention to the dollars.</p>

## :point_right: Accurate Mode

Accurate Mode runs the game's own Play Hand code for the selected cards inside a rolled-back sandbox and reads the score the game itself computes, so every installed mod is counted exactly as it would be in a real hand.

 - The game state is snapshotted first. Animations, sounds, saving, unlocks and statistics are switched off during the simulated hand, and the state is restored and verified afterwards. If it is ever not restored exactly, Accurate Mode switches itself off for the session.
 - If a simulated hand fails for any reason (for example a mod throws an error), that preview falls back to the original simulation described below. After 3 failures in a row it pauses for a short while.
 - Scoring done in coroutines (Talisman, balatro-utils async scoring) and custom event managers are supported.
 - Min/Max previews are produced by re-running the sandbox with every random roll forced to its extremes.
 - Two settings were added: **Accurate Mode** (on by default) and **Log Preview Accuracy**. The log writes `DVPreview_audit.log` in the Balatro save folder, comparing the preview with the real score after each played hand (`OK` or `DIFF`, which engine was used, the jokers and consumables involved, and `why=` when Accurate Mode was skipped).

## :point_right: Mod Compatibility

When Accurate Mode is off or falls back, this mod **only simulates vanilla jokers**. To support modded jokers, it is necessary to tell this mod how to simulate them, which requires writing a new function for each modded joker. Unfortunately, this is the best way I could see to bypass all animations and side-effects, to calculate exact/min/max previews simultaneously, and to make the simulation efficient. It will be up to the other mod developers to ensure that the preview is accurate for their mods.

### :arrow_forward: How to make your mod compatible?

See [Divvy's Simulation](https://github.com/DivvyCr/Balatro-Simulation?tab=readme-ov-file#how-to-add-modded-jokers)
