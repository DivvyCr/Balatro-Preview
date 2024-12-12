<h1 align="center">Divvy's Preview for Balatro</h1>

<div align="center">

![Version](https://img.shields.io/badge/latest-v3.0-blue.svg)
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

> [!CAUTION]
> This mod is currently **incompatible** with other mods.
> I am in the process of kick-starting the process of making the popular mods compatible.
> If you are a mod creator, please help me out by reading the *Mod Compatibility* section below.

## :point_right: See It In Action

<p align="center"><img src="gifs/DVPreview_Demo-2.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview updating in real-time.</p>

&nbsp;

<p align="center"><img src="gifs/DVPreview_Demo-3.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview being hidden with face-down cards.</p>

&nbsp;

<p align="center"><img src="gifs/DVPreview_Demo-4.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview updating in real-time, pay attention to the dollars.</p>

## :point_right: Mod Compatibility

By default, this mod **only simulates vanilla jokers**. To support modded jokers, it is necessary to tell this mod how to simulate them, which requires writing a new function for each modded joker. Unfortunately, this is the best way I could see to bypass all animations and side-effects, to calculate exact/min/max previews simultaneously, and to make the simulation efficient. It will be up to the other mod developers to ensure that the preview is accurate for their mods.

### :arrow_forward: How to make your mod compatible?

See [Divvy's Simulation](https://github.com/DivvyCr/Balatro-Simulation?tab=readme-ov-file#how-to-add-modded-jokers)

---

<p align="center">
<b>If you found this mod useful, consider supporting me!</b>
</p>

<p align="center">
<a href="https://www.buymeacoffee.com/divvyc" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>
