---
title: "EOG build: where to find the parts"
date: 2026-11-01
description: "Every part of the first DIY eye-movement sensor, with shops in the Netherlands, the EU and worldwide, prices and stock as checked on 1 November 2026, and what we could not find."
outcome: "Checked 1 Nov 2026"
tldr:
  - "The EXG Pill is not in stock at any Dutch or EU shop; in stock at Crowd Supply (US) and the maker (India)."
  - "Everything else is in stock in the Netherlands (Tinytronics, Kiwi) or at DigiKey NL, except a 500 mAh protected LiPo (only 1200 mAh in stock)."
  - "Cheapest from EU shops: about €79 (Pill on 4-week back-order). Simplest, all in stock: about €95–100."
  - "Nothing has been ordered; prices and stock change daily."
---

> This is a guide, not a recommendation to buy. Prices and stock change daily. Prices are as the shop showed them on 2026-11-01, **without shipping**, and "incl. VAT" / "excl. VAT" is written only where the page said so. Nothing here is a medical device. For why these parts were chosen and how to use them safely (battery only, never while charging), read [Build your own eye-movement sensor (EOG) with an ESP32](diy-eog-esp32.md) first.

UK shops (The Pi Hut, Pimoroni): since Brexit, an order to the Netherlands can bring Dutch VAT, customs handling fees and sometimes duty on top of the price. The same is true for US and Indian shops.

## 1. BioAmp EXG Pill (Upside Down Labs)

| Shop | Region | Product page | Price | Stock (2026-11-01) | Notes |
|---|---|---|---|---|---|
| Upside Down Labs store (maker) | India | [store.upsidedownlabs.tech](https://store.upsidedownlabs.tech/product/bioamp-exg-pill/) | ₹2,599 (1 Pill); ₹5,199 (2-pack); ₹19,999 (8-pack) | 28 / 20 / 2 in stock | Single kit includes 1 BioAmp Cable v3 (JST-PH to snap), 3 jumper cables, 12 gel electrodes. The site ships abroad by DHL but its banner sends international buyers to Tindie, DigiKey or Mouser. Shipping cost not checked |
| DigiKey NL | EU (ships from US) | [digikey.nl search, part 5075-0047-ND](https://www.digikey.nl/en/products/result?keywords=bioamp%20exg%20pill) | €34.40 (1 pc) | **0 in stock**, "standard lead time 4 weeks" | Page does not say whether cable or electrodes are included |
| Tindie (maker's store) | Worldwide | [1 Pill](https://www.tindie.com/products/upsidedownlabs/bioamp-exg-pill-sensor-for-ecg-emg-eog-or-eeg/), [2-pack](https://www.tindie.com/products/upsidedownlabs/bioamp-exg-pill-x2-sensor-for-ecg-emg-eog-eeg/) | US$34.49; US$69.00 | Not shown; page says shipping rates for the chosen country are not set yet | Kit contents only shown as an image, so not confirmed |
| Crowd Supply | Worldwide (US) | [EXG Pill](https://www.crowdsupply.com/upside-down-labs/bioamp-exg-pill) | US$69 Explorer Pack (2 Pills); US$249 (8) | In stock | Explorer: 2 Pills, 15 gel electrodes, 2 electrode cables, 6 alligator clips, headers. Shipping US$18 worldwide |
| Robu.in | India | (product pages blocked our checker, HTTP 403) | not checked | not checked | Search snippets show an "unassembled" version in stock |

Not found: Tinytronics, Kiwi, Opencircuit, Elektor, Antratek, Berrybase, Pimoroni, The Pi Hut. Mouser lists Upside Down Labs as a brand, but its pages did not load for us (not checked). No AliExpress or Amazon.nl clone found.

## 2. Seeed XIAO ESP32-C3

| Shop | Region | Product page | Price | Stock | Notes |
|---|---|---|---|---|---|
| Tinytronics | NL | [link](https://www.tinytronics.nl/nl/development-boards/microcontroller-boards/met-wi-fi/seeed-studio-xiao-esp32-c3) | €6.30 incl. VAT (€5.21 excl.) | 200+ in stock, Eindhoven | |
| Kiwi Electronics | NL | [link](https://www.kiwi-electronics.com/en/development-boards-213/seeed-studio-xiao-esp32c3-11039) | €5.82 incl. VAT (€4.89 excl.) | 198 in stock | |
| DigiKey NL | EU | [search 113991054](https://www.digikey.nl/en/products/result?keywords=113991054) | €4.66 excl. VAT | 23,068 | |
| Berrybase | DE | [link](https://www.berrybase.de/en/seeed-xiao-esp32c3-tiny-mcu-board-with-wlan-and-ble) | €7.90 incl. VAT | 100+ available | With or without headers |
| The Pi Hut | UK | [link](https://thepihut.com/collections/all/products/seeed-xiao-esp32c3) | £5.10 incl. UK VAT | In stock | Import costs, see top |
| Seeed Studio (maker) | China | [link](https://www.seeedstudio.com/Seeed-XIAO-ESP32C3-p-5431.html) | US$4.90 | In stock | |

## 3. ADS1115 16-bit ADC breakout

| Shop | Region | Product page | Price | Stock | Notes |
|---|---|---|---|---|---|
| Adafruit (maker) | US | [1085](https://www.adafruit.com/product/1085) | US$14.95 | In stock | |
| DigiKey NL | EU | [1528-1461-ND](https://www.digikey.nl/en/products/detail/1085/1528-1461-ND/5761229) | €13.27 excl. VAT (€16.06 incl.) | 2,927 | Genuine Adafruit 1085 |
| Opencircuit | NL | [link](https://opencircuit.shop/Product/ADS1115-16-Bit-ADC-4-Channel-Programmable-Gain) | €23.25 incl. VAT | 100 in external warehouse, 10–12 days | Listed as Adafruit 1085 |
| Berrybase | DE | [link](https://www.berrybase.de/adafruit-ads1115-16-bit-adc-4-kanal-mit-programmierbarem-verstaerker) | €15.90 incl. VAT | **Not available** | |
| Pimoroni | UK | [link](https://shop.pimoroni.com/products/adafruit-ads1115-16-bit-adc-4-channel-with-programmable-gain-amplifier) | not shown | **Pre-order** | |
| Tinytronics | NL | [generic module](https://www.tinytronics.nl/nl/sensoren/stroom-spanning/ads1115-adc-module-16-bit-i2c-4-kanalen) | €5.50 incl. VAT | 100+ in stock | **Unbranded clone-type module** ("Merkloos"); lower quality assurance |
| Tinytronics | NL | [DFRobot Gravity DFR0553](https://www.tinytronics.nl/en/sensors/current-voltage/dfrobot-gravity-i2c-ads1115-16-bit-adc-module) | €17.25 incl. VAT | 9 in stock | Branded alternative, same chip |

## 4. Protected 3.7 V LiPo (400–1000 mAh)

The XIAO ESP32-C3 has **solder pads** for the battery, not a plug. A JST-PH battery needs its plug cut off or a matching JST-PH socket soldered on. Check polarity: Tinytronics warns there is no standard polarity for LiPo JST plugs.

| Shop | Region | Product page | Price | Stock | Notes |
|---|---|---|---|---|---|
| Tinytronics | NL | [PKCELL 500 mAh LP503035](https://www.tinytronics.nl/nl/power/batterijen/li-po/pkcell-li-po-batterij-3.7v-500mah-jst-ph-lp503035) | €4.75 incl. VAT | **Not in stock** (2–4 weeks) | Protection circuit, JST-PH |
| Tinytronics | NL | [PKCELL 1200 mAh LP503562](https://www.tinytronics.nl/nl/power/batterijen/li-po/pkcell-li-po-batterij-3.7v-1200mah-jst-ph-lp503562) | €6.00 incl. VAT | 200+ in stock | Slightly above the range; protection IC S-8261, JST-PH, 65×36×5.3 mm, 24 g |
| Kiwi Electronics | NL | [PKCELL 500 mAh](https://www.kiwi-electronics.com/en/batteries-powerbanks-93/lithium-polymer-li-po-battery-3-7v-500mah-2200) | €5.94 incl. VAT | **Out of stock**, no backorder | Protection, JST-PH |
| Berrybase | DE | [LP-503035](https://www.berrybase.de/en/lp-503035-lithium-polymer-lipo-battery-3.7v-500mah-with-2-pin-jst-connector) | €5.10 incl. VAT | **Not available** | |
| The Pi Hut | UK | [500 mAh](https://thepihut.com/collections/all/products/500mah-3-7v-lipo-battery) | £6 | **Sold out** | |
| Adafruit | US | [1578](https://www.adafruit.com/product/1578) | US$7.95 | **Out of stock** | |

Not found: an in-stock 400–1000 mAh protected cell at a Dutch shop on the day.

## 5. Snap electrodes and snap cables

The maker's single EXG Pill kit already includes a **BioAmp Cable v3** (JST-PH to snaps) and 12 gel electrodes (maker's store page). DigiKey's and Tindie's contents are not confirmed. SparkFun-style cables end in a **3.5 mm audio jack**, so they need a jack socket to wire to the Pill.

| Shop | Region | Product page | Price | Stock | Notes |
|---|---|---|---|---|---|
| SparkFun (maker) | US | [SEN-12969, 10 × 24 mm](https://www.sparkfun.com/disposable-surface-emg-ecg-ekg-electrode-24mm-10-pack.html) | US$9.95 | In stock, "only 2 remaining" | **Ag/AgCl**-coated sensor, 4 mm snap |
| Opencircuit | NL | [same pads](https://opencircuit.shop/product/disposable-surface-emg-ecg-ekg-electrode-24mm) | €16.50 incl. VAT | External warehouse, 5–7 days | |
| The Pi Hut | UK | [same pads](https://thepihut.com/products/disposable-surface-emg-ecg-ekg-electrode-24mm-10-pack) | £9.60 | In stock, 12 left | |
| Mindfield | DE | [50 pre-gelled electrodes](https://mindfield-shop.com/en/product/ecg-eda-single-use-electrodes-adults/) | €14.90 incl. 19% VAT | Not stated | Ag/AgCl per image caption; size and snap size not stated |
| Tindie (Upside Down Labs) | Worldwide | [Neo gel electrodes, 100](https://www.tindie.com/products/upsidedownlabs/neo-gel-electrodes-msgst-27x-100pcs-pack/) | US$19.49 | 9 left | 3.2 × 2.5 cm, "Ag/AgCl" solid gel, stainless snap |
| Crowd Supply | Worldwide | [NPG Lite page, accessories](https://www.crowdsupply.com/upside-down-labs/neuro-playground-lite) | US$20 snap cables (10); US$20 tab hydrogel electrodes (100) | In stock | Made for NPG Lite; fit with the EXG Pill not checked |
| Opencircuit | NL | [SparkFun 3-lead cable CAB-12970](https://opencircuit.shop/product/sensor-cable-electrode-pads-3-connector) | €14.75 incl. VAT | External warehouse, 5–7 days | 3.5 mm jack |
| RobotShop EU | EU | [same cable](https://eu.robotshop.com/products/electrode-cable-3-lead) | €10.21 | In stock | 3.5 mm jack |
| Berrybase | DE | [same cable](https://www.berrybase.de/en/sparkfun-sensor-cable-electrode-pads-3-connections) | €10.50 | **Not available** | |

Not found: the BioAmp Cable v3 on its own at an EU shop (Robu.in lists it, page blocked for us).

## 6. 5 V boost module

| Shop | Region | Product page | Price | Stock | Notes |
|---|---|---|---|---|---|
| Adafruit (maker) | US | [MiniBoost 4654](https://www.adafruit.com/product/4654) | US$3.95 | In stock | TPS61023, 2–5 V in, 5.2 V out |
| DigiKey NL | EU | [search 4654](https://www.digikey.nl/en/products/result?keywords=adafruit%204654) | €3.51 excl. VAT | 1,853 | |
| The Pi Hut | UK | [MiniBoost](https://thepihut.com/products/adafruit-miniboost-5v-1a-tps61023) | £3.80 | In stock | |
| Pololu (maker) | US | [U1V10F5](https://www.pololu.com/product/2564) | US$7.95 | "Active and Preferred", backorders allowed | 0.5–5.5 V in |
| Opencircuit | NL | [U1V10F5](https://opencircuit.shop/Product/Pololu-5V-Step-Up-Voltage-Regulator-U1V10F5) | €7.10 incl. VAT | 619 in external warehouse, 5–7 days | |
| Tinytronics | NL | [generic 2 A 5 V boost](https://www.tinytronics.nl/en/power/voltage-converters/boost-(step-up)-converters/dc-dc-step-up-boost-converter-2a-5v-output) | €3.00 incl. VAT | 100+ | **Unbranded**, 2.7–5 V in, 80 mV ripple, no reverse-polarity protection |

Whether a boost is needed at all is still open (section 7). A switching converter also adds ripple near an amplifier, which is worth testing.

## 7. Optional: NPG Lite (all-in-one) and BITalino EOG (reference)

| Shop | Region | Product page | Price | Stock | Notes |
|---|---|---|---|---|---|
| Tindie (Upside Down Labs) | Worldwide | [NPG Lite Explorer](https://www.tindie.com/products/upsidedownlabs/neuro-playground-lite-npg-lite-explorer-pack/) | US$99 | "Only 2 left" | Includes 7 snap cables, 12 gel electrodes; **battery not included** |
| Crowd Supply | Worldwide | [NPG Lite](https://www.crowdsupply.com/upside-down-labs/neuro-playground-lite) | US$113 Explorer / US$179 Ninja / US$240 Beast | All **pre-order** | Ship dates shown (e.g. Ninja "Oct 30, 2026") look stale. Ninja lists a LiPo; Beast page contradicts itself |
| PLUX (maker) | PT (EU) | [EOG for BITalino](https://pluxbiosignals.com/products/electrooculography-eog-sensor) | €60.00 | No status shown, "Add to cart" | Needs a BITalino base: [BITalino Board €195, Plugged €225](https://www.pluxbiosignals.com/collections/bitalino). VAT treatment not stated |

## Not found / unclear

- **EXG Pill in NL/EU shops:** none found. DigiKey NL lists it with 0 stock. The closest in-stock sources are Crowd Supply (US) and the maker's Indian store.
- **EXG Pill supply voltage, conflicting:** datasheet says 5 V. The docs list "3.3 V / 5 V" and describe 3.3 V use via an output divider. Tindie lists "Input Voltage 4.5–40 V". A LiPo (3.0–4.2 V) is below the Tindie minimum, which is why a boost module is on the list. Test on the bench.
- **What DigiKey's and Tindie's single Pill include:** not confirmed.
- **Mouser.nl:** pages did not load, so all Mouser prices and stock are not checked. **Farnell, Reichelt, Elektor, Antratek:** not checked or not found for these items.
- **Robu.in:** blocked our checker, so not checked.
- **AliExpress / Amazon.nl clones:** no product pages found for any of these parts. The only clone-type items listed are the unbranded Tinytronics ADS1115 and boost modules.
- **Protected LiPo, 400–1000 mAh, in stock in NL:** not found. Only 1200 mAh was in stock.
- **Ag/AgCl:** confirmed for SparkFun pads, the maker's Neo gel pads and Mindfield's. Not confirmed for the EXG Pill kit's own electrodes.
- **Shipping costs and import VAT** for US, UK and Indian orders: not checked.

## Approximate baskets (one sensor channel)

**Cheapest realistic from EU shops (approximate, incl. VAT where shown, plus 3 shipping charges):**
DigiKey NL EXG Pill €34.40 excl. VAT (about €41.60 with 21% VAT, **back-order ~4 weeks**) + Tinytronics XIAO €6.30, generic ADS1115 €5.50, 1200 mAh LiPo €6.00 and boost €3.00 + Opencircuit SparkFun electrodes €16.50. **About €79**, plus a snap cable (~€10–15) if the DigiKey Pill turns out to come without one.

**Simplest basket (fewest shops, everything in stock):**
Crowd Supply Explorer Pack (2 Pills, cables, 15 electrodes) US$69 + US$18 shipping, plus one Tinytronics order (XIAO, ADS1115, LiPo, boost) €20.80. **About US$87 + €21, roughly €95–100**, before any import VAT on the Crowd Supply parcel. You get a spare Pill for a second channel. To use only genuine Adafruit boards, swap the Tinytronics ADS1115 and boost for DigiKey NL (€13.27 + €3.51 excl. VAT), which adds a third shop.

## Sources

- https://store.upsidedownlabs.tech/product/bioamp-exg-pill/
- https://store.upsidedownlabs.tech/
- https://www.digikey.nl/en/products/result?keywords=bioamp%20exg%20pill
- https://www.tindie.com/products/upsidedownlabs/bioamp-exg-pill-sensor-for-ecg-emg-eog-or-eeg/
- https://www.tindie.com/products/upsidedownlabs/bioamp-exg-pill-x2-sensor-for-ecg-emg-eog-eeg/
- https://www.crowdsupply.com/upside-down-labs/bioamp-exg-pill
- https://docs.upsidedownlabs.tech/hardware/bioamp/bioamp-exg-pill/index.html
- https://robu-prod-media.s3.ap-south-1.amazonaws.com/uploads/2024/04/BioAmp-EXG-Pill-Data-Sheet.pdf
- https://www.tinytronics.nl/nl/development-boards/microcontroller-boards/met-wi-fi/seeed-studio-xiao-esp32-c3
- https://www.kiwi-electronics.com/en/development-boards-213/seeed-studio-xiao-esp32c3-11039
- https://www.digikey.nl/en/products/result?keywords=113991054
- https://www.berrybase.de/en/seeed-xiao-esp32c3-tiny-mcu-board-with-wlan-and-ble
- https://thepihut.com/collections/all/products/seeed-xiao-esp32c3
- https://www.seeedstudio.com/Seeed-XIAO-ESP32C3-p-5431.html
- https://www.adafruit.com/product/1085
- https://www.digikey.nl/en/products/detail/1085/1528-1461-ND/5761229
- https://opencircuit.shop/Product/ADS1115-16-Bit-ADC-4-Channel-Programmable-Gain
- https://www.berrybase.de/adafruit-ads1115-16-bit-adc-4-kanal-mit-programmierbarem-verstaerker
- https://shop.pimoroni.com/products/adafruit-ads1115-16-bit-adc-4-channel-with-programmable-gain-amplifier
- https://www.tinytronics.nl/nl/sensoren/stroom-spanning/ads1115-adc-module-16-bit-i2c-4-kanalen
- https://www.tinytronics.nl/en/sensors/current-voltage/dfrobot-gravity-i2c-ads1115-16-bit-adc-module
- https://www.tinytronics.nl/nl/power/batterijen/li-po/pkcell-li-po-batterij-3.7v-500mah-jst-ph-lp503035
- https://www.tinytronics.nl/nl/power/batterijen/li-po/pkcell-li-po-batterij-3.7v-1200mah-jst-ph-lp503562
- https://www.kiwi-electronics.com/en/batteries-powerbanks-93/lithium-polymer-li-po-battery-3-7v-500mah-2200
- https://www.berrybase.de/en/lp-503035-lithium-polymer-lipo-battery-3.7v-500mah-with-2-pin-jst-connector
- https://thepihut.com/collections/all/products/500mah-3-7v-lipo-battery
- https://www.adafruit.com/product/1578
- https://www.sparkfun.com/disposable-surface-emg-ecg-ekg-electrode-24mm-10-pack.html
- https://opencircuit.shop/product/disposable-surface-emg-ecg-ekg-electrode-24mm
- https://thepihut.com/products/disposable-surface-emg-ecg-ekg-electrode-24mm-10-pack
- https://mindfield-shop.com/en/product/ecg-eda-single-use-electrodes-adults/
- https://www.tindie.com/products/upsidedownlabs/neo-gel-electrodes-msgst-27x-100pcs-pack/
- https://opencircuit.shop/product/sensor-cable-electrode-pads-3-connector
- https://eu.robotshop.com/products/electrode-cable-3-lead
- https://www.berrybase.de/en/sparkfun-sensor-cable-electrode-pads-3-connections
- https://www.adafruit.com/product/4654
- https://www.digikey.nl/en/products/result?keywords=adafruit%204654
- https://thepihut.com/products/adafruit-miniboost-5v-1a-tps61023
- https://www.pololu.com/product/2564
- https://opencircuit.shop/Product/Pololu-5V-Step-Up-Voltage-Regulator-U1V10F5
- https://www.tinytronics.nl/en/power/voltage-converters/boost-(step-up)-converters/dc-dc-step-up-boost-converter-2a-5v-output
- https://www.tindie.com/products/upsidedownlabs/neuro-playground-lite-npg-lite-explorer-pack/
- https://www.crowdsupply.com/upside-down-labs/neuro-playground-lite
- https://pluxbiosignals.com/products/electrooculography-eog-sensor
- https://www.pluxbiosignals.com/collections/bitalino
