# php74-el7-build

CentOS 7（EL7）向けに、Remi リポジトリの PHP 7.4.33 SRPM をビルドするスクリプトと、ビルド済み RPM の公開リポジトリです。対象リビジョンは **-32** と **-33** の2つで、いずれもビルド済み RPM を Releases からダウンロードできます。

PHP 7.4 は公式サポートが終了（EOL）しており、2026年11月に公開された脆弱性に対する公式修正は 7.4 には提供されません。Remi が公開する 7.4.33 の新しいリビジョンには、それらの修正のバックポートが含まれます。本リポジトリは、そのリビジョンを CentOS 7 上でビルドできるようにし、成果物を公開するものです。

## -32 と -33 の違い

どちらも PHP 本体は 7.4.33 で、**セキュリティ修正の内容は同一**です（11月公開の脆弱性12件のバックポートは -32 で入りました）。違いは、リンクする PostgreSQL クライアントライブラリだけです。

| 項目 | -32 | -33 |
|---|---|---|
| 公開日 | 2026-11-18 | 2026-11-24 |
| セキュリティ修正 | 11月分の12件を含む | -32 と同一（追加なし） |
| PostgreSQL ライブラリ | CentOS 7 標準の `postgresql-libs`（9.2） | PGDG の libpq（15/16系） |
| 導入時の追加作業 | なし | php-pgsql を使う場合は `yum swap postgresql-libs libpq5` が必要 |
| ビルド時の追加リポジトリ | なし | PGDG が必要 |

選び方の目安:

- **-32**: PostgreSQL まわりの構成を変えたくない環境向け。セキュリティ修正は -33 と同じものが入っています
- **-33**: 最新リビジョンで揃えたい場合。php-pgsql を使う環境では、導入時に libpq の切り替えが発生します

リビジョンごとの変更内容の詳細は、ブログ記事 [PHP 7.4.33-31／-32／-33の違いを整理する](https://blog.tyis.co.jp/%E3%82%BB%E3%82%AD%E3%83%A5%E3%83%AA%E3%83%86%E3%82%A3/%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC%E9%81%8B%E7%94%A8/php/php74-33-31-32-33-differences/) を参照してください。

## ビルド済み RPM（Releases）

- [v7.4.33-33](https://github.com/tyis/php74-el7-build/releases/tag/v7.4.33-33) — RPM 35個＋SRPM＋チェックサム（SHA256SUMS-7.4.33-33.txt）
- [v7.4.33-32](https://github.com/tyis/php74-el7-build/releases/tag/v7.4.33-32) — RPM 35個＋SRPM＋チェックサム（SHA256SUMS-7.4.33-32.txt）

チェックサムは各 Releases への添付のほか、リポジトリの `checksums/` ディレクトリにもリビジョン別に置いています。

### 検証結果（共通）

どちらのリビジョンも、クリーンな CentOS 7.9 環境へのインストール検証済みです。

- `php -v` → PHP 7.4.33、読み込みモジュール 70個、`php-fpm -t` 成功
- RPM の changelog に 2026年11月公開分の修正（CVE-2026-129538、CVE-2026-129496、CVE-2026-129289、CVE-2026-129292 など）が含まれることを確認
- `%check` テストスイート: -33 はパス 9,116件／失敗 1件、-32 はパス 9,119件／失敗 1件（失敗した1件はいずれも `disk_free_space`、実行環境依存のテストでビルド自体の不具合ではありません）

-32 では加えて、php-pgsql が標準の `postgresql-libs`（9.2.24）の libpq で起動時警告なく読み込めることを確認しています。

## 自分でビルドする

同梱の `build.sh` は **-33 用**です。-32 をビルドする場合は、後述の調整のうち libpq に関する2点（spec の `libpq-devel` 書き換えと PGDG リポジトリ追加）が不要になります。

### 環境準備

スクリプトは CentOS 7 の中で動かすものです。ホスト側に CentOS 7 が無くても、Docker があれば始められます。

```bash
# ホスト側
docker run -it --name php74build centos:7
```

コンテナに入ったら、その中で以下の「使い方」に進みます。成果物を取り出す場合は、別ターミナルから：

```bash
docker cp php74build:/root/rpmbuild/RPMS./RPMS
```

必要なもの:

- CentOS 7 / RHEL 7 環境（コンテナ・VM・実機いずれも可）
- root 権限
- ネットワーク接続（vault.centos.org、Fedora アーカイブ、Remi、-33 の場合は PGDG へアクセスします）
- 空きディスク 約10GB、所要時間 約1時間（CPU性能により前後します）

### 使い方

```bash
curl -LO https://raw.githubusercontent.com/tyis/php74-el7-build/main/build.sh
chmod +x build.sh
./build.sh
```

完了すると、RPM が `~/rpmbuild/RPMS/x86_64/` に出力されます。

### EL7 向けの調整内容

素の CentOS 7 ではそのままビルドできないため、スクリプト内で次の調整を行っています。

1. **EOL 対応**: CentOS 7 はサポート終了のため、標準リポジトリを vault.centos.org（7.9.2009）、EPEL を Fedora アーカイブへ向け直します。
2. **SRPM の展開方法**: Remi の SRPM は Rich Dependencies を使うため EL7 の rpm ではインストールできず、`rpm2cpio` で展開します。
3. **spec の調整**:
- `with_libgd` を 0 に（バンドル版ではなくシステムの libgd を使用）
- `oniguruma5php-devel` → `oniguruma-devel`（EPEL のパッケージ名に合わせる）
- ICU のバージョン制約を除去（EL7 の ICU は 50 ですが、spec は -32／-33 で `>= 78` を要求します。バージョン番号に依存しない正規表現で除去するため、リビジョンが変わっても使えます）
- `libpq-devel` → `libpq5-devel`（-33 で `postgresql-devel` から変更されましたが、その名前のパッケージは EL7 のリポジトリに存在せず、PGDG リポジトリの `libpq5-devel` が実体です）
4. **PGDG リポジトリの追加**: 上記 `libpq5-devel` の取得元として PostgreSQL 公式 PGDG（EL7 向け 15）を追加します。

調整箇所の差分は `php74.spec.diff`（-33 用）として同梱しています。

## 実行時の注意（php-pgsql を使う場合）

- **-33**: PGDG の libpq（15/16系）でビルドされているため、CentOS 7 標準の `postgresql-libs`（9.2）の libpq では pgsql 拡張が `undefined symbol: lo_truncate64` でロードできません。php-pgsql を使う環境では、PGDG の `libpq5` へ切り替えてください（pgsql を使わないモジュールには影響ありません）。

```bash
yum swap postgresql-libs libpq5
```

- **-32**: 標準の `postgresql-libs` のままで動作します。切り替えは不要です。

## 注意

- PHP 7.4 は EOL です。本ビルドは移行までの暫定対応としてご利用ください。
- Remi SRPM のライセンス・商標は各権利者に帰属します。本リポジトリは東洋インターネットサービス株式会社によるビルド手順の公開です。

## 関連

- ブログ記事: [-31／-32／-33 の違い](https://blog.tyis.co.jp/%E3%82%BB%E3%82%AD%E3%83%A5%E3%83%AA%E3%83%86%E3%82%A3/%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC%E9%81%8B%E7%94%A8/php/php74-33-31-32-33-differences/) ／ [-33 のビルド手順](https://blog.tyis.co.jp/%E3%82%BB%E3%82%AD%E3%83%A5%E3%83%AA%E3%83%86%E3%82%A3/%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC%E9%81%8B%E7%94%A8/php/php74-33-33-centos7-build-guide/)
- 会社サイト: https://www.tyis.co.jp/
