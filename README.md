<h1 align="center">Divvy's Preview for Balatro</h1>

<p align="center"><img src="gifs/DVPreview_Demo-1.gif" style="width:100%" /></p>

<p align="center">
<b>Simulate the score and the dollars that you will get by playing the selected cards!</b>
</p>

## Installation

 0. Install [Steamodded](https://github.com/Steamopollys/Steamodded)
 1. Download the latest release of this mod, [here](https://github.com/DivvyCr/Balatro-Preview/releases/latest).
 2. Copy the downloaded folder to `C:\Users\[USER]\AppData\Roaming\Balatro\`
 3. Launch the game!

## Features

 - Score and dollar preview **without side-effects**!
 - **Updates in real-time** when changing selected cards, changing joker order, or using consumables!
 - Can preview score even when cards are face-down!
 - Perfectly **predicts random effects**...
 - ... or not! There is an option to show the **minimum and maximum possible scores** when probabilities are involved!

## See It In Action

<p align="center"><img src="gifs/DVPreview_Demo-2.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview updating in real-time.</p>

&nbsp;

<p align="center"><img src="gifs/DVPreview_Demo-3.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview being hidden with face-down cards.</p>

&nbsp;

<p align="center"><img src="gifs/DVPreview_Demo-4.gif" style="width:90%" /></p>
<p align="center">Demonstration for the preview updating in real-time, pay attention to the dollars.</p>

## Use My Simulation!

If you are a mod developer, feel free to copy the `Mods\DVSimulate.lua` file to your mod and use the simulation function!
Ideally, I would like `DVSimulate.lua` to be a sort of library for mods to use, but I have not yet looked into the best ways to make that work with Steamodded.
If you have ideas, feel free to open an issue.

### Mod Compatibility

This mod is focused only on vanilla Balatro.
If you find errors in score calculation that seem to involve another mod, you may open an issue here, but I will not fix it unless it is a very popular mod.
Instead, I should hopefully work with other mod developers to make it as easy as possible to adjust the simulation for compatibility.
It should be as easy as checking whether `DV.SIM` is defined and then creating custom advice for the `DV.SIM.run(..)` function.
To be clear, this would be placed in the other mod.
Unfortunately, this approach depends on the order in which mods are loaded, so if you know how to influence that, let me know by opening an issue.

---

<p align="center">
<a href="https://www.buymeacoffee.com/divvyc" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>
