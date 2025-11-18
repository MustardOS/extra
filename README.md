# Notice!

The following files are to keep previous compatibility with current/past MustardOS releases. These files will be removed by the end of the year 2025.

```
2508_1_Canada_Goose.json
extra_data.json
```

# muOS Base/Extra Core + Builder

To build all cores defined in `data/core.json`, run:

```bash
./build.sh -a
```

To build specific cores, specify their names as arguments:

```bash
./build.sh -c dosbox-pure sameboy
```

To purge any existing core repositories add the `-p` switch:

```bash
./build.sh -p -c dosbox-pure sameboy
```

### Please Note

* Before using this build system, run a manual build outside of it to verify that all required commands and variables are correctly configured.
* This build system assumes you have already configured and initialised a toolchain.

## Core Structure

* `source` - The repository URL where it the core will clone from
* `branch` - The repository branch of the above source
* `directory` - Usually the name of the repository but can be anything
* `output` - The end file that is compiled for processing
* `make.file` - The file which make calls upon
* `make.args` - Additional arguments that is used alongside make
* `make.target` - A specific target to use with make if required
* `symbols` - Set it to `1` if you require debug symbols
* `commands.pre-make` - Commands to run _**before**_ make is run
* `commands.post-make` - Commands that are run _**after**_ successful compilation

The `branch` and `commands` sections are completely optional and can be omitted.

### Example Core (SameBoy)

```json
{
  "sameboy": {
    "source": "https://github.com/LIJI32/SameBoy",
    "directory": "SameBoy",
    "output": "sameboy_libretro.so",
    "make": {
      "file": "Makefile",
      "args": "",
      "target": ""
    },
    "symbols": 0,
    "commands": {
      "pre-make": [
        "make clean >/dev/null 2>&1",
        "printf '\\n\\t\\tBuilding Boot ROMs\\n'",
        "make bootroms >/dev/null 2>&1",
        "printf '\\n\\t\\tPre-generating Libretro Source\\n'",
        "make libretro >/dev/null 2>&1",
        "cd libretro"
      ],
      "post-make": [
        "cd .."
      ]
    }
  }
}
```

## Additional Notes

* **SameBoy** core requires the [RGBDS (Rednex Game Boy Development System)](https://github.com/gbdev/rgbds/) to be installed to your existing toolchain, all instructions are on that page.

These are additional systems and core packages that can be installed by the on-device **Core Downloader** mechanism.

## Current Core List

***

| System                               | Cores                                                                                                                                                                                                                                                                                   |
|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Amstrad                              | `crocods_libretro.so`<br>`cap32_libretro.so`                                                                                                                                                                                                                                            |
| Arcade - FB Alpha 2012               | `fbalpha2012_cps1_libretro.so`<br>`fbalpha2012_cps2_libretro.so`<br>`fbalpha2012_cps3_libretro.so`<br>`fbalpha2012_neogeo_libretro.so`                                                                                                                                                  |
| Arcade - MAME                        | `mame_libretro.so`                                                                                                                                                                                                                                                                      |
| Arcade - MAME 078 Plus               | `mame078plus_libretro.so`                                                                                                                                                                                                                                                               |
| Arcade - MAME 139                    | `mame0139_libretro.so`                                                                                                                                                                                                                                                                  |
| Arcade - MAME 2000                   | `mame2000_libretro.so`                                                                                                                                                                                                                                                                  |
| Arcade - MAME 2003 Midway            | `mame2003_midway_libretro.so`                                                                                                                                                                                                                                                           |
| Arcade - MAME 2003 Plus              | `mame2003_plus_libretro.so`                                                                                                                                                                                                                                                             |
| Arcade - MAME 2010                   | `mame2010_libretro.so`                                                                                                                                                                                                                                                                  |
| Arduboy                              | `ardens_libretro.so`<br>`arduous_libretro.so`                                                                                                                                                                                                                                           |
| Atari 5200                           | `a5200_libretro.so`<br>`atari800_libretro.so`                                                                                                                                                                                                                                           |
| Atari 7800                           | `prosystem_libretro.so`                                                                                                                                                                                                                                                                 |
| Atari 800                            | `atari800_libretro.so`                                                                                                                                                                                                                                                                  |
| Atari Jaguar                         | `virtualjaguar_libretro.so`                                                                                                                                                                                                                                                             |
| Atari ST-STE-TT-Falcon               | `hatari_libretro.so`<br>`hatarib_libretro.so`                                                                                                                                                                                                                                           |
| Bandai WonderSwan Color              | `mednafen_wswan_libretro.so`                                                                                                                                                                                                                                                            |
| ChaiLove                             | `chailove_libretro.so`                                                                                                                                                                                                                                                                  |
| CHIP-8                               | `jaxe_libretro.so`                                                                                                                                                                                                                                                                      |
| ColecoVision                         | `bluemsx_libretro.so`<br>`gearcoleco_libretro.so`                                                                                                                                                                                                                                       |
| Commodore 128                        | `vice_x128_libretro.so`                                                                                                                                                                                                                                                                 |
| Commodore 64                         | `vice_x64sc_libretro.so`<br>`vice_xscpu64_libretro.so`                                                                                                                                                                                                                                  |
| Commodore Amiga                      | `km_puae_xtreme_amped_2k24_libretro.so`<br>`puae_libretro.so`<br>`uae4arm_libretro.so`                                                                                                                                                                                                  |
| Commodore CBM-II                     | `vice_xcbm2_libretro.so`<br>`vice_xcbm5x0_libretro.so`                                                                                                                                                                                                                                  |
| Commodore PET                        | `vice_xpet_libretro.so`                                                                                                                                                                                                                                                                 |
| Commodore VIC-20                     | `vice_xvic_libretro.so`                                                                                                                                                                                                                                                                 |
| Discrete Integrated Circuit Emulator | `dice_libretro.so`                                                                                                                                                                                                                                                                      |
| Dragon and Tandy 8-bit               | `ext-xroar`                                                                                                                                                                                                                                                                             |
| Fairchild Channel F                  | `freechaf_libretro.so`                                                                                                                                                                                                                                                                  |
| Galaksija Retro Computer             | `galaksija_libretro.so`                                                                                                                                                                                                                                                                 |
| Game Tank                            | `libgametank_libretro.so`                                                                                                                                                                                                                                                                 |
| GCE Vectrex                          | `vecx_libretro.so`                                                                                                                                                                                                                                                                      |
| Handheld Electronic - Game and Watch | `gw_libretro.so`                                                                                                                                                                                                                                                                        |
| Java J2ME                            | `freej2me_libretro.so`                                                                                                                                                                                                                                                                  |
| Karaoke                              | `pocketcdg_libretro.so`                                                                                                                                                                                                                                                                 |
| LowRes NX                            | `lowresnx_libretro.so`                                                                                                                                                                                                                                                                  |
| Lua Engine                           | `lutro_libretro.so`                                                                                                                                                                                                                                                                     |
| Magnavox Odyssey - VideoPac          | `o2em_libretro.so`                                                                                                                                                                                                                                                                      |
| Mattel Intellivision                 | `freeintv_libretro.so`                                                                                                                                                                                                                                                                  |
| Mega Duck - Cougar Boy               | `sameduck_libretro.so`                                                                                                                                                                                                                                                                  |
| Microsoft MSX                        | `bluemsx_libretro.so`<br>`fmsx_libretro.so`                                                                                                                                                                                                                                             |
| NEC PC-8000 - PC-8800 Series         | `quasi88_libretro.so`                                                                                                                                                                                                                                                                   |
| NEC PC98                             | `np2kai_libretro.so`<br>`nekop2_libretro.so`                                                                                                                                                                                                                                            |
| NEC PC-FX                            | `mednafen_pcfx_libretro.so`                                                                                                                                                                                                                                                             |
| Nintendo DS                          | `desmume2015_libretro.so`<br>`ext-drastic-legacy`<br>`melondsds_libretro.so`<br>`melonds_libretro.so`                                                                                                                                                                                   |
| Nintendo Famicom Disk System         | `fceumm_libretro.so`<br>`mesen_libretro.so`<br>`nestopia_libretro.so`                                                                                                                                                                                                                   |
| Nintendo Game Boy                    | `DoubleCherryGB_libretro.so`<br>`fixgb_libretro.so`<br>`tgbdual_libretro.so`<br>`vbam_libretro.so`                                                                                                                                                                                      |
| Nintendo Game Boy Advance            | `mednafen_gba_libretro.so`<br>`mgba_rumble_libretro.so`<br>`vbam_libretro.so`<br>`vba_next_libretro.so`                                                                                                                                                                                 |
| Nintendo Game Boy Color              | `DoubleCherryGB_libretro.so`<br>`fixgb_libretro.so`<br>`tgbdual_libretro.so`<br>`vbam_libretro.so`                                                                                                                                                                                      |
| Nintendo N64                         | `mupen64plus_libretro.so`<br>`parallel_n64_libretro.so`<br>`km_ludicrousn64_2k22_xtreme_amped_libretro.so`                                                                                                                                                                              |
| Nintendo NES - Famicom               | `bnes_libretro.so`<br>`mesen_libretro.so`                                                                                                                                                                                                                                               |
| Nintendo Pokemon Mini                | `pokemini_libretro.so`                                                                                                                                                                                                                                                                  |
| Nintendo SNES - SFC                  | `bsnes2014_performance_libretro.so`<br>`bsnes_cplusplus98_libretro.so`<br>`bsnes_mercury_performance_libretro.so`<br>`bsnes_libretro.so`<br>`mesen-s_libretro.so`<br>`snes9x2005_plus_libretro.so`<br>`snes9x2005_libretro.so`<br>`snes9x2010_libretro.so`<br>`snes9x_next_libretro.so` |
| Onscripter                           | `onsyuri_libretro.so`<br>`onscripter_libretro.so`                                                                                                                                                                                                                                       |
| OpenBOR                              | `ext-openbor4432`<br>`ext-openbor6412`<br>`ext-openbor7142`<br>`ext-openbor7530`                                                                                                                                                                                                        |
| Philips CDi                          | `same_cdi_libretro.so`                                                                                                                                                                                                                                                                  |
| Pyxel                                | `ext-pyxel`                                                                                                                                                                                                                                                                             |
| Quake                                | `tyrquake_libretro.so`                                                                                                                                                                                                                                                                  |
| Quake II                             | `vitaquake2_libretro.so`<br>`vitaquake2-rogue_libretro.so`<br>`vitaquake2-xatrix_libretro.so`<br>`vitaquake2-zaero_libretro.so`                                                                                                                                                         |
| ScummVM                              | `scummvm_libretro.so`                                                                                                                                                                                                                                                                   |
| Sega Mega Drive - Genesis            | `genesis_plus_gx_expanded_libretro.so`                                                                                                                                                                                                                                                  |
| Sega Pico                            | `genesis_plus_gx_wide_libretro.so`<br>`genesis_plus_gx_libretro.so`<br>`picodrive_libretro.so`                                                                                                                                                                                          |
| Sega Saturn                          | `mednafen_saturn_libretro.so`<br>`yabause_libretro.so`<br>`ext-yabasanshiro-hle`<br>`ext-yabasanshiro-bios`<br>`yabasanshiro_libretro.so`                                                                                                                                               |
| Sega SG-1000                         | `bluemsx_libretro.so`<br>`gearsystem_libretro.so`<br>`genesis_plus_gx_libretro.so`                                                                                                                                                                                                      |
| Sharp X1                             | `x1_libretro.so`                                                                                                                                                                                                                                                                        |
| Sharp X68000                         | `px68k_libretro.so`                                                                                                                                                                                                                                                                     |
| Sinclair ZX 81                       | `81_libretro.so`                                                                                                                                                                                                                                                                        |
| Sinclair ZX Spectrum                 | `fuse_libretro.so`                                                                                                                                                                                                                                                                      |
| SNK Neo Geo                          | `geolith_libretro.so`                                                                                                                                                                                                                                                                   |
| Sony PlayStation                     | `mednafen_psx_libretro.so`                                                                                                                                                                                                                                                              |
| SVI - ColecoVision - SG1000          | `bluemsx_libretro.so`                                                                                                                                                                                                                                                                   |
| Texas Instruments TI-83              | `numero_libretro.so`                                                                                                                                                                                                                                                                    |
| TIC-80                               | `tic80_libretro.so`                                                                                                                                                                                                                                                                     |
| The 3DO Company - 3DO                | `opera_libretro.so`                                                                                                                                                                                                                                                                     |
| Uzebox                               | `uzem_libretro.so`                                                                                                                                                                                                                                                                      |
| VeMUlator                            | `vemulator_libretro.so`                                                                                                                                                                                                                                                                 |
| Vircon32                             | `vircon32_libretro.so`                                                                                                                                                                                                                                                                  |
| WASM-4                               | `wasm4_libretro.so`                                                                                                                                                                                                                                                                     |
| Watara Supervision                   | `potator_libretro.so`                                                                                                                                                                                                                                                                   |
=======