import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../scheduling.dart';
import '../ui/stair_theme.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_native_controls.dart';

class OnlineSiteEditor extends StatefulWidget {
  const OnlineSiteEditor({
    super.key,
    required this.store,
    this.site,
    this.initialName = '',
    this.initialUrl = '',
  });
  final GiriStore store;
  final OnlineSite? site;
  final String initialName;
  final String initialUrl;
  @override
  State<OnlineSiteEditor> createState() => _OnlineSiteEditorState();
}

class _OnlineSiteEditorState extends State<OnlineSiteEditor> {
  final _form = GlobalKey<FormState>();
  late final _siteId = widget.site?.id ?? widget.store.newId();
  late final _name = TextEditingController(
    text: widget.site?.name ?? widget.initialName,
  );
  late final _url = TextEditingController(
    text: widget.site?.url ?? widget.initialUrl,
  );
  late final _affiliation = TextEditingController(
    text: widget.site?.affiliation ?? '',
  );
  late final _block = TextEditingController(text: widget.site?.block ?? '');
  late final _memo = TextEditingController(text: widget.site?.memo ?? '');
  late SiteRecurrence _recurrence =
      widget.site?.recurrence ?? SiteRecurrence.weekly;
  late int _weekday =
      widget.site?.weekday ??
      defaultSubmissionStart(DateTime.now(), widget.store.preferences).weekday;
  late int _posting =
      widget.site?.submissionDays ?? widget.store.preferences.submissionDays;
  late int _voting =
      widget.site?.votingDays ?? widget.store.preferences.votingDays;
  late DateTime _time = DateTime(
    2000,
    1,
    1,
    widget.site?.startHour ?? widget.store.preferences.submissionStartHour,
    widget.site?.startMinute ?? widget.store.preferences.submissionStartMinute,
  );
  bool _saving = false;
  @override
  void dispose() {
    for (final field in [_name, _url, _affiliation, _block, _memo]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final site = OnlineSite(
        id: _siteId,
        name: _name.text.trim(),
        url: _url.text.trim(),
        recurrence: _recurrence,
        weekday: _weekday,
        startHour: _time.hour,
        startMinute: _time.minute,
        submissionDays: _posting,
        votingDays: _voting,
        affiliation: _affiliation.text.trim(),
        block: _block.text.trim(),
        memo: _memo.text,
      );
      await widget.store.saveOnlineSite(site);
      if (site.recurrence == SiteRecurrence.weekly) {
        await widget.store.createSiteCycle(site.id, join: false);
        await widget.store.createSiteCycle(site.id, weekOffset: 1, join: false);
      }
      if (mounted) {
        StairNativeControls.saveFeedback();
        Navigator.pop(context, site);
      }
    } catch (_) {
      if (mounted) showStairMessage(context, 'サイトを保存できませんでした。', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String hint, {
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: controller == _url ? TextInputType.url : null,
      maxLines: controller == _memo ? null : 1,
      decoration: InputDecoration(hintText: hint),
      validator: required
          ? (text) => text == null || text.trim().isEmpty ? '入力してください' : null
          : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(
      title: Text(widget.site == null ? 'サイトを登録' : 'サイト設定'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: StairSaveButton(
            onPressed: _saving ? null : _save,
            saving: _saving,
          ),
        ),
      ],
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StairFormSection(
            title: '基本情報',
            icon: CupertinoIcons.globe,
            accent: StairColors.online,
            children: [
              _field(_name, 'サイト名 *', required: true),
              _field(_url, 'サイトURL'),
              _field(_affiliation, '所属（例：一部）'),
              _field(_block, 'お題・ブロック（例：お題A）'),
            ],
          ),
          StairFormSection(
            title: '投稿・投票の周期',
            icon: CupertinoIcons.calendar,
            accent: StairColors.online,
            children: [
              StairMenuRow<SiteRecurrence>(
                label: '開催',
                value: _recurrence,
                items: const {
                  SiteRecurrence.weekly: '毎週',
                  SiteRecurrence.irregular: '不定期',
                },
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _recurrence = value),
              ),
              if (_recurrence == SiteRecurrence.weekly)
                StairMenuRow<int>(
                  label: '投稿開始の曜日',
                  value: _weekday,
                  items: const {
                    1: '月曜日',
                    2: '火曜日',
                    3: '水曜日',
                    4: '木曜日',
                    5: '金曜日',
                    6: '土曜日',
                    7: '日曜日',
                  },
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _weekday = value),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: StairTimeButton(
                  label: '投稿開始',
                  value: _time,
                  date: DateTime(2000, 1, 1),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _time = value);
                        },
                ),
              ),
              StairMenuRow<int>(
                label: '投稿期間',
                value: _posting,
                items: {
                  for (var days = 1; days <= 30; days++) days: '$days日',
                  if (_posting > 30) _posting: '$_posting日',
                },
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _posting = value),
              ),
              StairMenuRow<int>(
                label: '投票期間',
                value: _voting,
                items: {
                  for (var days = 1; days <= 30; days++) days: '$days日',
                  if (_voting > 30) _voting: '$_voting日',
                },
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _voting = value),
              ),
            ],
          ),
          StairFormSection(
            title: 'メモ',
            icon: CupertinoIcons.pencil,
            accent: StairColors.memo,
            children: [_field(_memo, 'サイトのルール・メモ')],
          ),
        ],
      ),
    ),
  );
}
