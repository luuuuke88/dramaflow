import 'package:dramaflow/src/engine/credentials.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late DbCredentialStore store;

  setUp(() {
    db = openEngineDb(':memory:');
    store = DbCredentialStore(db);
  });

  tearDown(() => db.close());

  test('未写入时读取返回 null，不抛错', () async {
    expect(await store.read('dramaflow.provider.openai.api-key'), isNull);
  });

  test('写入后可读回原值', () async {
    const ref = 'dramaflow.provider.openai.api-key';
    await store.write(ref, 'sk-secret-123');
    expect(await store.read(ref), 'sk-secret-123');
    // 落到 o_secret 表，而非 o_setting（后者会被配置导出）。
    expect(
        db.select('SELECT value FROM o_secret WHERE ref=?', [ref]).single['value'],
        'sk-secret-123');
  });

  test('重复写入同一 ref 覆盖旧值（upsert）', () async {
    const ref = 'dramaflow.provider.deepseek.api-key';
    await store.write(ref, 'old');
    await store.write(ref, 'new');
    expect(await store.read(ref), 'new');
    expect(db.select('SELECT COUNT(*) n FROM o_secret WHERE ref=?', [ref])
        .single['n'], 1);
  });

  test('删除后读取返回 null', () async {
    const ref = 'dramaflow.provider.xai.api-key';
    await store.write(ref, 'grok-key');
    await store.delete(ref);
    expect(await store.read(ref), isNull);
  });

  test('删除不存在的 ref 不抛错', () async {
    await store.delete('dramaflow.provider.nope.api-key');
  });
}
