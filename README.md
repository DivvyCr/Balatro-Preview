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

To begin with, an example of the basic structure for making modded jokers compatible is as follows:

```lua
if DV and DV.SIM then -- Check that Divvy's Simulation is loaded

   DV.SIM.JOKERS.simulate_[JOKERID1] = function(joker, context)
      if context.cardarea == G.jokers and context.before and not context.blueprint then
         -- Upgrade joker, or simulate any other 'before' effects
      elseif context.cardarea == G.jokers and context.global then
         -- Simulate main effect application
      end
   end

   DV.SIM.JOKERS.simulate_[JOKERID2] = function(joker, context)
      if context.cardarea == G.play and context.individual then
         -- Simulate joker effect on each played card
      elseif context.cardarea == G.hand and context.individual then
         -- Simulate joker effect on each held card
      end
   end

   -- All other jokers...
end
```

If you've created modded jokers before, then the structure of each function should be familiar.
The only big differences are: the repetition of `if context.cardarea ...` for each function, and the new `context.global` property which I introduced to specify when the global joker effects are being applied (as opposed to per-card effects).
You should specify `context.global` whenever your joker's effect was in the `else` branch of all contexts.
The best way to get a feel for all this is to look at the examples down below.

> [!IMPORTANT]
> The simulation code **must use my mod's custom functions**, all of which are listed below.
> This is necessary because I use a stripped-down version of all objects, namely `Card`, which in turn means that the default functions like `Card:get_id()` may cause errors.
> Again, this is a consequence of avoiding animations and side-effects.

Lastly, **you don't have to write functions for all modded jokers** &mdash; only those that affect score or money during a played hand. For instance, here is a sample of jokers that I ignore in the vanilla game:
 - "Four Fingers", because it does not affect the score nor the money directly;
 - "Trading Card", because its effect is applied after a discard, not after a play;
 - "Marble Joker", because its effect applies during blind selection, not during a play;
 - "Delayed Gratification", because its effect applies after the round ends, not during a play.

If in doubt, feel free to ask for help on Discord!

### :arrow_forward: What are the custom functions?

The following are the core functions for manipulating the simulated chips and mult.
You will usually just use one argument to manipulate all chips and mult equally (ie. for exact/min/max preview), like `DV.SIM.add_mult(3)`.
However, if your joker has a chance element to it, you will have to specify all three arguments.
 - `DV.SIM.add_chips(exact, [min], [max])`
 - `DV.SIM.add_mult(exact, [min], [max])`
 - `DV.SIM.x_mult(exact, [min], [max])`
 - `DV.SIM.add_dollars(exact, [min], [max])`
 - `DV.SIM.add_reps(n)`
   - This adds `n` repetitions for the current played or held card; see examples below.
 - `DV.SIM.get_probabilistic_extremes(random_value, odds, reward, default)`
   - This is a helper function for getting the `exact`, `min`, and `max` values from your joker, if it relies on chance.
   - It assumes that your joker uses the standard approach to chance: `random_value < probability/odds`.
   - Its main purpose is to account for guaranteed probabilities, like "2 in 2 chance", which would mean that `exact = min = max`.

<details><summary><b>[CLICK ME] Jokers relying on `t_chips`, `t_mult`, or `s_mult`:</b></summary>

If your modded joker leverages the game's built-in properties for chips or mult (based on hand type or suit), then you can use the following functions:
 - `DV.SIM.JOKERS.add_type_chips(joker, context)`
 - `DV.SIM.JOKERS.add_type_mult(joker, context)`
 - `DV.SIM.JOKERS.add_suit_mult(joker, context)`

```lua
DV.SIM.JOKERS.simulate_lusty_joker = function(joker, context)
   DV.SIM.JOKERS.add_suit_mult(joker, context)
end


DV.SIM.JOKERS.simulate_jolly = function(joker, context)
    DV.SIM.JOKERS.add_type_mult(joker, context)
end

DV.SIM.JOKERS.simulate_sly = function(joker, context)
    DV.SIM.JOKERS.add_type_chips(joker, context)
end
```

</details>

<details><summary><b>[CLICK ME] Jokers relying on automatic `x_mult` application:</b></summary>

If your modded joker leverages the game's built-in x-mult calculation, then you can use the following function:
 - `DV.SIM.JOKERS.x_mult_if_global(joker, context)`

However, **only do this if you know what you are doing**. If in doubt, have a look at the function definition, [here](https://github.com/DivvyCr/Balatro-Preview/blob/da295c058e86911b653d978cc8c19e365586f7df/Mods/DVSimulate.lua#L1432).

```lua
DV.SIM.JOKERS.simulate_madness = function(joker, context)
    DV.SIM.JOKERS.x_mult_if_global(joker, context)
end
```

</details>

```lua
DV.SIM.JOKERS.simulate_bloodstone = function(joker, context)
   if context.cardarea == G.play and context.individual then
      if DV.SIM.is_suit(context.other_card, "Hearts") and not context.other_card.debuff then
         local exact_xmult, min_xmult, max_xmult = DV.SIM.get_probabilistic_extremes(pseudorandom("bloodstone"), joker.ability.extra.odds, joker.ability.extra.Xmult, 1)
         DV.SIM.x_mult(exact_xmult, min_xmult, max_xmult)
      end
   end
end
```

---

The following drop-downs contain all available properties, and below them are the new property retrieval functions.

<details><summary><b>[CLICK ME] Available card properties:</b></summary>

```lua
local card_data = {
   rank = card_obj.base.id,                -- Number 2-14 (where 11-14 is Jack through Ace)
   suit = card_obj.base.suit,              -- "Spades", "Hearts", "Clubs", or "Diamonds"
   base_chips = card_obj.base.nominal,     -- Number 2-10 (default number of chips scored)
   ability = copy_table(card_obj.ability), -- Mirrors Card object
   edition = copy_table(card_obj.edition), -- Mirrors Card object
   seal = card_obj.seal,                   -- "Red", "Purple", "Blue", or "Gold"
   debuff = card_obj.debuff,               -- Boolean
   lucky_trigger = {}                      -- Holds values for exact/min/max triggers
}
```

</details>

<details><summary><b>[CLICK ME] Available joker properties:</b></summary>

```lua
local joker_data = {
   id = [...],
   ability = copy_table(joker.ability), -- Mirrors Card object
   edition = copy_table(joker.edition), -- Mirrors Card object
   rarity = joker.config.center.rarity  -- Number 1-4 (Common, Uncommon, Rare, Legendary)
}
```

</details>

 - `DV.SIM.get_rank(card_data)`
   - Returns the card's rank (2-14) or a unique negative value for Stone Cards.
 - `DV.SIM.is_rank(card_data, ranks)`
   - Check for a single rank by using a number argument: `DV.SIM.is_rank(card, 9)`
   - Check for multiple ranks by using a table argument: `DV.SIM.is_rank(card, {11, 12, 13})`
 - `DV.SIM.is_face(card_data)`
   - Checks for ranks 11, 12, 13, taking into account Pareidolia.
 - `DV.SIM.is_suit(card_data, suit, [ignore_debuff])`
   - Checks for suit, taking into account Stone Cards, Wild Cards, and Smeared Joker.
   - Usually returns `false` if card is debuffed, unless `ignore_debuff == true`.

```lua
DV.SIM.JOKERS.simulate_walkie_talkie = function(joker, context)
   if context.cardarea == G.play and context.individual then
      if DV.SIM.is_rank(context.other_card, {10, 4}) and not context.other_card.debuff then
         DV.SIM.add_chips(joker.ability.extra.chips)
         DV.SIM.add_mult(joker.ability.extra.mult)
      end
   end
end
```

---

The following are the new card manipulation functions.
In general, instead of `card:set_property(new_property)` you will have to write `DV.SIM.set_property(card, new_property)`.
 - `DV.SIM.set_ability(card_data, center)`
 - `DV.SIM.set_edition(card_data, edition)`

```lua
DV.SIM.JOKERS.simulate_midas_mask = function(joker, context)
   if context.cardarea == G.jokers and context.before and not context.blueprint then
      for _, card in ipairs(context.full_hand) do
         if DV.SIM.is_face(card) then
            DV.SIM.set_ability(card, G.P_CENTERS.m_gold)
         end
      end
   end
end
```

### :arrow_forward: Examples

The best source of examples is the default `DV.SIM.JOKERS` definition, found [here](https://github.com/DivvyCr/Balatro-Preview/blob/da295c058e86911b653d978cc8c19e365586f7df/Mods/DVSimulate.lua#L467).

<details><summary><b>[CLICK ME] Hack:</b></summary>

```lua
DV.SIM.JOKER.simulate_hack = function(joker, context)
   if context.cardarea == G.play and context.repetition then
      if not context.other_card.debuff and DV.SIM.is_rank(context.other_card, {2, 3, 4, 5}) then
         DV.SIM.add_reps(joker.ability.extra)
      end
   end
end
```

</details>

<details><summary><b>[CLICK ME] Ride The Bus:</b></summary>

```lua
DV.SIM.JOKERS.simulate_ride_the_bus = function(joker, context)
   -- Upgrade/Reset, as necessary:
   if context.cardarea == G.jokers and context.before and not context.blueprint then
      local faces = false
      for _, scoring_card in ipairs(context.scoring_hand) do
         if DV.SIM.is_face(scoring_card) then faces = true end
      end
      if faces then
         joker.ability.mult = 0
      else
         joker.ability.mult = joker.ability.mult + joker.ability.extra
      end
   end

   -- Apply mult:
   if context.cardarea == G.jokers and context.global then
      DV.SIM.add_mult(joker.ability.mult)
   end
end
```

</details>

<details><summary><b>[CLICK ME] Hiker:</b></summary>

```lua
DV.SIM.JOKERS.simulate_hiker = function(joker, context)
   if context.cardarea == G.play and context.individual then
      if not context.other_card.debuff then
         context.other_card.ability.perma_bonus = (context.other_card.ability.perma_bonus or 0) + joker.ability.extra
      end
   end
end
```

</details>

<details><summary><b>[CLICK ME] Business Card:</b></summary>

```lua
DV.SIM.JOKERS.simulate_business = function(joker, context)
   if context.cardarea == G.play and context.individual then
      if DV.SIM.is_face(context.other_card) and not context.other_card.debuff then
         local exact_dollars, min_dollars, max_dollars = DV.SIM.get_probabilistic_extremes(pseudorandom("business"), joker.ability.extra, 2, 0)
         DV.SIM.add_dollars(exact_dollars, min_dollars, max_dollars)
      end
   end
end
```

</details>

<details><summary><b>[CLICK ME] Idol:</b></summary>

```lua
DV.SIM.JOKERS.simulate_idol = function(joker, context)
   if context.cardarea == G.play and context.individual then
      if DV.SIM.is_rank(context.other_card, G.GAME.current_round.idol_card.id) and
         DV.SIM.is_suit(context.other_card, G.GAME.current_round.idol_card.suit) and
         not context.other_card.debuff
      then
         DV.SIM.x_mult(joker.ability.extra)
      end
   end
end
```

</details>

---

<p align="center">
<b>If you found this mod useful, consider supporting me!</b>
</p>

<p align="center">
<a href="https://www.buymeacoffee.com/divvyc" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>
