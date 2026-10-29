# Community Overlays

Pickles (games) and Wasabi (video and music) both offer an overlay catalogue, read from `data/overlays.json`. An
overlay is a transparent PNG drawn over the running game or video. You can list your own overlay in the catalogue by
hosting the images yourself and adding an entry that links to them.

The `overlay/` folder and the `MustardOS` entries in the catalogue are the overlays MustardOS ships with. They are
looked after by the MustardOS crew, so please do not add files to that folder or change those entries.

## How it works

1. Pickles or Wasabi fetches `data/overlays.json` from the `main` branch of this repository.
2. A device only shows overlays that include an image for its own screen resolution, for example `640x480`.
3. Selecting an overlay downloads it, checks each image against its `sha256`, and saves it on the device as
   `<resolution>/<author>/<file name>.png` inside the player's own overlay folder:
   - Pickles: `/run/muos/storage/pickles/overlay/`
   - Wasabi: `/run/muos/storage/wasabi/overlay/`
4. When an installed image no longer matches the `sha256` in the catalogue, the overlay shows as an update.

The same images are offered in both players.

## Hosting your overlay

Put your PNG files in your own public repository, for example on GitHub, and link to each raw file. On GitHub that is
the `raw.githubusercontent.com` link, not the `github.com/.../blob/...` page. A folder for each resolution keeps things
tidy:

```
https://raw.githubusercontent.com/YourName/your-overlays/refs/heads/main/640x480/my-overlay.png
https://raw.githubusercontent.com/YourName/your-overlays/refs/heads/main/720x720/my-overlay.png
```

Any `https://` link that serves the file directly will work.

Every change to an image changes its SHA-256, and devices refuse an image that does not match the catalogue. If you
link to a branch such as `main`, the overlay stops installing as soon as you push a change, until a pull request here
updates the hash. To avoid that, link to a tag or commit instead, and send a pull request with the new links, hashes
and `version` when you are ready to release a change.

## Making the images

- Save as PNG with an alpha channel, at the full screen size of each resolution.
- Each image must be no larger than 8 MiB.
- Cover as many of these resolutions as you can, since each one maps to a group of devices:
  `640x480`, `720x480`, `720x720`, `1024x768`, `1280x720` and `1920x1080`.
- Use the same file name for every resolution.

The Overlay Opacity setting scales the image alpha on the device, so author each overlay at a fairly strong alpha and
let users tone it down.

### Testing on a device

Copy your PNG into `/run/muos/storage/pickles/overlay/<resolution>/` or `/run/muos/storage/wasabi/overlay/<resolution>/`
on the device, using the device's own resolution, then pick it from the overlay list in that player. Since the catalogue
offers every overlay to both players, try it over a game and over a video before submitting.

## Catalogue entry

```json
{
  "name": "My Overlay",
  "author": "YourName",
  "version": "1",
  "viewport": [0, 16],
  "images": [
    {
      "resolution": "640x480",
      "url": "https://raw.githubusercontent.com/YourName/your-overlays/v1/640x480/my-overlay.png",
      "sha256": "<sha256 of the file>"
    },
    {
      "resolution": "720x720",
      "url": "https://raw.githubusercontent.com/YourName/your-overlays/v1/720x720/my-overlay.png",
      "sha256": "<sha256 of the file>",
      "viewport": [0, 120]
    },
    {
      "resolution": "1280x720",
      "url": "https://raw.githubusercontent.com/YourName/your-overlays/v1/1280x720/my-overlay.png",
      "sha256": "<sha256 of the file>",
      "viewport": [0, 0]
    }
  ]
}
```

The entry `viewport` applies to every image that does not set its own. An image with its own `viewport` uses that
instead, and `[0, 0]` on an image clears the entry offset for that image alone. In the example above:

- `640x480` has no `viewport`, so it uses the entry offset of `[0, 16]`.
- `720x720` uses its own offset of `[0, 120]`.
- `1280x720` uses `[0, 0]`, so it has no offset even though the entry sets one.

Both are optional and can be left out when no offset is needed.

| Field      | Rules                                                                                                         |
|------------|---------------------------------------------------------------------------------------------------------------|
| `name`     | Shown in the catalogue. Up to 63 characters, no leading or trailing spaces.                                   |
| `author`   | Your name or handle. Up to 63 characters. It also becomes the folder the overlay is saved into on the device. |
| `version`  | A string, for example `"1"`. Raise it whenever any image changes.                                             |
| `viewport` | Optional. `[x, y]` pixel offset for every image, from -4096 to 4096. Defaults to `[0, 0]`.                    |
| `images`   | One object for each resolution, up to 8 images.                                                               |

Each image takes:

| Field        | Rules                                                                                  |
|--------------|----------------------------------------------------------------------------------------|
| `resolution` | `WIDTHxHEIGHT`, matching the device screen exactly.                                    |
| `url`        | A direct `https://` link to the raw `.png` file.                                       |
| `sha256`     | The 64 character SHA-256 of the exact file at `url`.                                   |
| `viewport`   | Optional. `[x, y]` offset for this image only, from -4096 to 4096. `[0, 0]` resets it. |

Every image in an overlay is saved under the file name of the first image's `url`. Keep that file name to letters,
numbers, `-` and `_`.

The list is kept in alphabetical order by `name`.

**Important:** one broken entry stops the whole catalogue loading in both Pickles and Wasabi on every device. A missing
field, an `http://` link or a malformed hash all count. Please check your entry before opening a pull request.

## Making a pull request

1. Fork this repository and create a branch, for example `overlay/my-overlay`.
2. Get the SHA-256 of each exact file its `url` serves:

   ```sh
   curl -sL "<raw url>" | sha256sum
   ```

3. Add your entry to `data/overlays.json` in alphabetical order by `name`. This file is the only one your pull request
   should change.
4. Check the catalogue still loads:

   ```sh
   jq -e 'def viewport: . == null or (type == "array" and length == 2
       and all(.[]; tostring | test("^-?[0-9]+$") and (tonumber | fabs) <= 4096));
     all(.[]; (.name | length) > 0 and (.author | length) > 0 and (.version | type) == "string"
       and (.viewport | viewport) and (.images | length) > 0 and (.images | length) <= 8
       and all(.images[]; (.resolution | test("^[0-9]+x[0-9]+$")) and (.viewport | viewport)
       and (.url | startswith("https://")) and (.sha256 | test("^[0-9a-fA-F]{64}$"))))' data/overlays.json
   ```

   This prints `true` when every entry is usable.

5. Open the pull request with a link to your repository, a short description of the overlay and a screenshot or two
   from a device. Mention if the overlay only suits games or only suits video.

To update an overlay later, send another pull request that changes your entry's links (if they point at a tag or
commit), hashes and `version`.
