import 'package:flutter_test/flutter_test.dart';
import 'package:dramaflow/src/engine/db.dart';
import 'package:dramaflow/src/engine/config.dart';
import 'package:dramaflow/src/engine/pipeline_policy.dart';

void main() {
  group('ActionPolicyMeta', () {
    test('构造默认', () {
      final meta = ActionPolicyMeta();
      expect(meta.costsMoney, false);
      expect(meta.destructive, false);
    });

    test('构造自定义', () {
      final meta = ActionPolicyMeta(costsMoney: true, destructive: false);
      expect(meta.costsMoney, true);
      expect(meta.destructive, false);
    });
  });

  group('actionPolicyByTaskClass', () {
    test('包含 11 个 taskClass', () {
      expect(actionPolicyByTaskClass.length, 11);
    });

    test('所有生成类任务都收费', () {
      const taskClasses = [
        'event_generation',
        'script_generation',
        'asset_extraction',
        'asset_prompt_polish',
        'director_plan_generation',
        'storyboard_table_generation',
        'asset_image_generation',
        'storyboard_generate',
        'storyboard_image_generation',
        'video_generation',
        'audio_bind',
      ];
      for (final taskClass in taskClasses) {
        expect(actionPolicyByTaskClass[taskClass]?.costsMoney, true,
            reason: '$taskClass should cost money');
      }
    });

    test('生成类任务都不破坏元数据', () {
      for (final meta in actionPolicyByTaskClass.values) {
        expect(meta.destructive, false);
      }
    });
  });

  group('destructiveActionKeys', () {
    test('包含 9 个破坏动作', () {
      expect(destructiveActionKeys.length, 9);
    });

    test('包括删除与清空系列', () {
      expect(destructiveActionKeys, contains('delete_assets'));
      expect(destructiveActionKeys, contains('delete_scripts'));
      expect(destructiveActionKeys, contains('delete_storyboards'));
      expect(destructiveActionKeys, contains('delete_video'));
      expect(destructiveActionKeys, contains('clear_tracks'));
      expect(destructiveActionKeys, contains('write_script'));
      expect(destructiveActionKeys, contains('note_delete'));
      expect(destructiveActionKeys, contains('clear_chat'));
      expect(destructiveActionKeys, contains('clear_all_data'));
    });
  });

  group('checkAction 队列任务（costsMoney 维度）', () {
    test('taskClass 无需确认（confirmMoney=0）', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmMoney': '0'});

      final verdict =
          checkAction(config, taskClass: 'event_generation', autoMode: false);
      expect(verdict, PolicyVerdict.allow);
    });

    test('taskClass 需确认（confirmMoney=1，非 auto）', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmMoney': '1'});

      final verdict =
          checkAction(config, taskClass: 'event_generation', autoMode: false);
      expect(verdict, PolicyVerdict.confirmMoney);
    });

    test('taskClass auto 模式放行', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmMoney': '1'});

      final verdict =
          checkAction(config, taskClass: 'event_generation', autoMode: true);
      expect(verdict, PolicyVerdict.allow);
    });

    test('默认值 confirmMoney=1', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      // 不修改，使用默认值

      final verdict =
          checkAction(config, taskClass: 'video_generation', autoMode: false);
      expect(verdict, PolicyVerdict.confirmMoney);
    });
  });

  group('checkAction 破坏动作（destructive 维度）', () {
    test('destructiveKey 无需确认（confirmDestructive=0）', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmDestructive': '0'});

      final verdict = checkAction(config, destructiveKey: 'delete_assets');
      expect(verdict, PolicyVerdict.allow);
    });

    test('destructiveKey 需确认（confirmDestructive=1，非 auto）', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmDestructive': '1'});

      final verdict = checkAction(config, destructiveKey: 'delete_assets');
      expect(verdict, PolicyVerdict.confirmDestructive);
    });

    test('destructiveKey auto 模式也需确认', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmDestructive': '1'});

      final verdict =
          checkAction(config, destructiveKey: 'delete_assets', autoMode: true);
      expect(verdict, PolicyVerdict.confirmDestructive);
    });

    test('默认值 confirmDestructive=1', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      // 不修改，使用默认值

      final verdict = checkAction(config, destructiveKey: 'clear_all_data');
      expect(verdict, PolicyVerdict.confirmDestructive);
    });
  });

  group('checkAction 其他场景', () {
    test('未知 taskClass → allow', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmMoney': '1'});

      final verdict =
          checkAction(config, taskClass: 'unknown_task', autoMode: false);
      expect(verdict, PolicyVerdict.allow);
    });

    test('未知 destructiveKey → allow', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update({'policy.confirmDestructive': '1'});

      final verdict = checkAction(config, destructiveKey: 'unknown_action');
      expect(verdict, PolicyVerdict.allow);
    });

    test('既不提供 taskClass 也不提供 destructiveKey → allow', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);

      final verdict = checkAction(config);
      expect(verdict, PolicyVerdict.allow);
    });

    test('同时提供 taskClass 和 destructiveKey → taskClass 优先', () {
      final db = openEngineDb(':memory:');
      final config = EngineConfig(db, isMobile: false);
      config.update(
          {'policy.confirmMoney': '1', 'policy.confirmDestructive': '0'});

      final verdict = checkAction(config,
          taskClass: 'event_generation', destructiveKey: 'delete_assets');
      // taskClass 优先，应返回 confirmMoney
      expect(verdict, PolicyVerdict.confirmMoney);
    });
  });

  group('checkAction 全矩阵测试', () {
    final taskClasses = [
      'event_generation',
      'script_generation',
      'asset_extraction',
      'asset_prompt_polish',
      'director_plan_generation',
      'storyboard_table_generation',
      'asset_image_generation',
      'storyboard_generate',
      'storyboard_image_generation',
      'video_generation',
      'audio_bind',
    ];

    test('11 个 taskClass × confirmMoney 开/关 × autoMode 真/假', () {
      for (final taskClass in taskClasses) {
        for (final confirmMoneyValue in ['0', '1']) {
          for (final autoMode in [true, false]) {
            final db = openEngineDb(':memory:');
            final config = EngineConfig(db, isMobile: false);
            config.update({'policy.confirmMoney': confirmMoneyValue});

            final verdict =
                checkAction(config, taskClass: taskClass, autoMode: autoMode);

            if (confirmMoneyValue == '1' && !autoMode) {
              expect(verdict, PolicyVerdict.confirmMoney,
                  reason:
                      '$taskClass confirmMoney=$confirmMoneyValue autoMode=$autoMode');
            } else {
              expect(verdict, PolicyVerdict.allow,
                  reason:
                      '$taskClass confirmMoney=$confirmMoneyValue autoMode=$autoMode');
            }
          }
        }
      }
    });

    test('9 个 destructiveKey × confirmDestructive 开/关', () {
      final destructiveKeys = [
        'delete_assets',
        'delete_scripts',
        'delete_storyboards',
        'delete_video',
        'clear_tracks',
        'write_script',
        'note_delete',
        'clear_chat',
        'clear_all_data',
      ];

      for (final key in destructiveKeys) {
        for (final confirmDestructiveValue in ['0', '1']) {
          final db = openEngineDb(':memory:');
          final config = EngineConfig(db, isMobile: false);
          config.update({'policy.confirmDestructive': confirmDestructiveValue});

          final verdict = checkAction(config, destructiveKey: key);

          if (confirmDestructiveValue == '1') {
            expect(verdict, PolicyVerdict.confirmDestructive,
                reason: '$key confirmDestructive=$confirmDestructiveValue');
          } else {
            expect(verdict, PolicyVerdict.allow,
                reason: '$key confirmDestructive=$confirmDestructiveValue');
          }
        }
      }
    });
  });
}
