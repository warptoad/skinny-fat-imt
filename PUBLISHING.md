# Publishing `skinny-imt` and `fat-imt` to npm under `@warptoad`

This guide publishes **only** the `skinny-imt` and `fat-imt` Solidity packages to npm
under the `@warptoad` org, without waiting on any zk-kit merge.

Published packages:

-   **[@warptoad/skinny-imt.sol](https://www.npmjs.com/package/@warptoad/skinny-imt.sol)**
-   **[@warptoad/fat-imt.sol](https://www.npmjs.com/package/@warptoad/fat-imt.sol)**

---

## What has already been set up (done, on this branch)

All the packaging config is already in place on the **`published-package`** branch.
It was kept on this branch on purpose, so it does **not** conflict with the upstream
zk-kit repo (which publishes these under the `@zk-kit` scope). Nothing below needs to
be redone — it's here just so you know what changed:

-   `packages/skinny-imt/contracts/package.json` was renamed from `@zk-kit/skinny-imt.sol`
    to **`@warptoad/skinny-imt.sol`**, its version was reset to `0.0.1`, and its
    `repository` / `homepage` / `bugs` were pointed at `warptoad/skinny-fat-imt`.
-   `packages/fat-imt/contracts/package.json` got the same treatment as
    **`@warptoad/fat-imt.sol`**.
-   The `poseidon2-evm` dependency was added to both (the `.sol` files import it, but it
    was previously undeclared).
-   The `files` field was tightened to `!**/test/**` so the nested test contracts no longer
    ship in the published tarball.
-   The root and outer-workspace `package.json` files remain `private: true` — only the
    two `contracts/` subfolders are publishable.

> **Layout note:** the published package is the `contracts/` subfolder, not the outer
> package dir. So consumers import from the package root, e.g.
> `import "@warptoad/skinny-imt.sol/poseidon2/SkinnyIMTPoseidon2.sol";`

---

## 1. Log in to npm (first time only)

You need an npm account that is a member of the `@warptoad` org with publish rights.
This repo uses **Yarn 4**, so log in with Yarn's npm client:

```bash
yarn npm login          # username, password, + OTP if you have 2FA
yarn npm whoami         # sanity check — should print your npm username
```

Once you've logged in, you can skip this step on future publishes.

---

## 2. (Optional) Check what will ship

```bash
cd packages/skinny-imt/contracts && yarn pack --dry-run; cd -
cd packages/fat-imt/contracts    && yarn pack --dry-run; cd -
```

You should see the source `.sol` files, `interfaces/`, `poseidon/`, `poseidon2/`,
`sha256/`, `README.md`, `LICENSE` — and **no** `*/test/*.sol` files.

---

## 3. Publish

Target each package **by name** — this works from anywhere in the repo and can't
accidentally hit the private root/outer workspaces:

```bash
yarn workspace @warptoad/skinny-imt.sol npm publish --access public
yarn workspace @warptoad/fat-imt.sol    npm publish --access public
```

Add `--otp=<code>` if npm asks for a 2FA code.

> ⚠️ Do **not** run the repo's `yarn version:publish` script. It runs
> `yarn workspaces foreach -A --no-private npm publish`, which would try to publish
> **all seven** `contracts` packages (imt, lean-imt, lazy-imt, lazytower, excubiae too).
> The two by-name commands above keep it to just skinny + fat.
>
> Also note: `yarn npm publish` (without `yarn workspace <name>`) publishes whichever
> workspace your shell is currently in — from the repo root or `packages/skinny-imt/`
> that's a `private` workspace, which fails with _"Private workspaces cannot be
> published."_ The by-name form avoids this entirely.

---

## 4. Verify and use

```bash
npm view @warptoad/skinny-imt.sol
npm view @warptoad/fat-imt.sol
```

Or open the pages directly:

-   https://www.npmjs.com/package/@warptoad/skinny-imt.sol
-   https://www.npmjs.com/package/@warptoad/fat-imt.sol

A consumer installs and imports like:

```bash
yarn add @warptoad/skinny-imt.sol
```

```solidity
import {SkinnyIMTPoseidon2} from "@warptoad/skinny-imt.sol/poseidon2/SkinnyIMTPoseidon2.sol";
```

---

## 5. Publishing new versions later

npm **will not let you republish an existing version number**. To ship an update:

1. Bump `version` in the relevant `contracts/package.json` (e.g. `0.0.1` → `0.0.2`).
    - `0.0.x` = anything can change (pre-1.0).
    - After `1.0.0`: patch = fixes, minor = additions, major = breaking changes.
2. Re-run the matching by-name publish command from §3.

Tip: `yarn version patch` (run inside the `contracts/` folder) bumps the number for you.
