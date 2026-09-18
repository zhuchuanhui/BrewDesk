# BrewDesk

macOS向けHomebrew管理アプリです。

## タグからDMGを作成

`v1.2.3` のタグ番号がアプリ本体のバージョンとDMG名に自動反映されます。

```sh
./scripts/build_and_package.sh v1.2.3
```

生成物:

- `outputs/BrewDesk-1.2.3.dmg`
- `BrewDesk.app` 内の `CFBundleShortVersionString=1.2.3`
- `BrewDesk.app` 内の `CFBundleVersion=1.2.3`

