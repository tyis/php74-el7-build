# php74-el7-build

CentOS 7 (EL7) 向けに、Remi リポジトリの PHP 7.4.33 SRPM（リビジョン -33）をビルドするスクリプトと成果物です。

PHP 7.4 は公式サポートが終了しており、2026年11月に公開された脆弱性（Critical を含む18件）に対する公式修正は 7.4 には提供されません。Remi が公開する 7.4.33 の新しいリビジョンには、それらの修正バックポートが含まれます。本リポジトリは、その最新リビジョン -33 を CentOS 7 上でビルドできるようにしたものです。

## 環境準備

スクリプトは CentOS 7 の中で動かすものです。ホスト側に CentOS 7 が無くても、Docker があれば始められます。

### Docker を使う場合（推奨）

```bash
# ホスト側
docker run -it --name php74build centos:7
```

コンテナに入ったら、その中で以下の「使い方」に進みます。成果物を取り出す場合は、別ターミナルから：

```bash
docker cp php74build:/root/rpmbuild/RPMS ./RPMS
```

### 必要なもの

- CentOS 7 / RHEL 7 環境（コンテナ・VM・実機いずれも可）
- root 権限
- ネットワーク接続（vault.centos.org、Fedora アーカイブ、Remi、PGDG へアクセスします）
- 空きディスク 約10GB、所要時間 約1時間（CPU性能により前後します）

## 使い方

```bash
curl -LO https://raw.githubusercontent.com/tyis/php74-el7-build/main/build.sh
chmod +x build.sh
./build.sh
```

完了すると、RPM が `~/rpmbuild/RPMS/x86_64/` に出力されます。

## EL7 向けの調整内容

素の CentOS 7 ではそのままビルドできないため、スクリプト内で次の調整を行っています。

1. **EOL 対応**: CentOS 7 はサポート終了のため、標準リポジトリを vault.centos.org（7.9.2009）、EPEL を Fedora アーカイブへ向け直します。
2. **SRPM の展開方法**: Remi の SRPM は Rich Dependencies を使うため EL7 の rpm ではインストールできず、`rpm2cpio` で展開します。
3. **spec の調整（4か所）**:
   - `with_libgd` を 0 に（バンドル版ではなくシステムの libgd を使用）
   - `oniguruma5php-devel` → `oniguruma-devel`（EPEL のパッケージ名に合わせる）
   - ICU のバージョン制約を除去（EL7 の ICU は 50 ですが、spec は -31 で `>= 74`、-33 で `>= 78` を要求します。バージョン番号に依存しない正規表現で除去するため、リビジョンが変わっても使えます）
   - `libpq-devel` → `libpq5-devel`（-33 で `postgresql-devel` から変更されましたが、その名前のパッケージは EL7 のリポジトリに存在せず、PGDG リポジトリの `libpq5-devel` が実体です）
4. **PGDG リポジトリの追加**: 上記 `libpq5-devel` の取得元として PostgreSQL 公式 PGDG（EL7 向け 15）を追加します。

## 成果物と検証結果（2026-11-25 実施）

ビルド済み RPM は [Releases（v7.4.33-33）](https://github.com/tyis/php74-el7-build/releases/tag/v7.4.33-33) に添付しています（RPM 35個＋SRPM、個別にダウンロードできます）。

### -32 の RPM もあります（libpq へ切り替えたくない環境向け）

-33 の libpq 切り替え（導入時の `yum swap postgresql-libs libpq5`）を避けたい環境向けに、1つ前のリビジョン **-32** の RPM もビルドして [Releases（v7.4.33-32）](https://github.com/tyis/php74-el7-build/releases/tag/v7.4.33-32) に添付しています。-32 は11月公開の脆弱性12件のバックポートを含み（セキュリティ内容は -33 と同一）、php-pgsql は CentOS 7 標準の `postgresql-libs`（9.2）の libpq でそのまま動作します（PGDG リポジトリ・swap ともに不要）。クリーンな CentOS 7.9 での導入検証済みです（PHP 7.4.33、モジュール70個、php-fpm 設定テスト成功、起動時警告なし）。ビルド時の spec 調整は libgd・oniguruma・ICU の3か所のみで、libpq の調整は含みません。

- 生成 RPM: x86_64 **35個**（約71MB）＋ SRPM 1個
- ビルド所要時間: 約83分（小規模 VM での実績。環境により大きく変動します）
- `%check` テストスイート: 総数 15,967件／実行 9,158件／**パス 9,116件**／失敗 1件／スキップ 6,809件
  - 失敗した1件は `disk_free_space`（実行環境依存のテスト）で、ビルド自体の不具合ではありません
- クリーンな CentOS 7.9 環境へのインストール検証済み
  - `php -v` → PHP 7.4.33、読み込みモジュール 70個、`php-fpm -t` 成功
  - RPM の changelog に 2026年11月公開分の修正（CVE-2026-129538、CVE-2026-129496、CVE-2026-129289、CVE-2026-129292 など）が含まれることを確認

## 実行時の注意（php-pgsql を使う場合）

-33 は PGDG の libpq（15/16系）でビルドされています。CentOS 7 標準の `postgresql-libs`（9.2）の libpq では、pgsql 拡張が `undefined symbol: lo_truncate64` でロードできません。php-pgsql を使う環境では、PGDG の `libpq5` へ切り替えてください。

```bash
yum swap postgresql-libs libpq5
```

（pgsql を使わないモジュールには影響ありません）

## 注意

- PHP 7.4 は EOL です。本ビルドは移行までの暫定対応としてご利用ください。
- Remi SRPM のライセンス・商標は各権利者に帰属します。本リポジトリは東洋インターネットサービス株式会社によるビルド手順の公開です。

## 関連

- ブログ解説記事: [PHP 7.4.33-33をCentOS 7でビルドする](https://blog.tyis.co.jp/%E3%82%BB%E3%82%AD%E3%83%A5%E3%83%AA%E3%83%86%E3%82%A3/%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC%E9%81%8B%E7%94%A8/php/php74-33-33-centos7-build-guide/)
- 会社サイト: https://www.tyis.co.jp/
