import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/persian_format.dart';
import '../models/calorie_targets.dart';

class CalorieTargetsForm extends StatefulWidget {
  const CalorieTargetsForm({
    required this.buttonLabel,
    required this.onSave,
    this.initialTargets,
    super.key,
  });

  final CalorieTargets? initialTargets;
  final String buttonLabel;
  final Future<void> Function(CalorieTargets targets) onSave;

  @override
  State<CalorieTargetsForm> createState() => _CalorieTargetsFormState();
}

class _CalorieTargetsFormState extends State<CalorieTargetsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _trainingController;
  late final TextEditingController _restController;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _trainingController = TextEditingController(
      text: widget.initialTargets?.trainingDayCalories.toString() ?? '',
    );
    _restController = TextEditingController(
      text: widget.initialTargets?.restDayCalories.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _trainingController.dispose();
    _restController.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final parsed = int.tryParse(westernDigits(value ?? ''));
    if (parsed == null) return 'یک عدد صحیح وارد کنید.';
    if (parsed <= 0 || parsed > 20000) {
      return 'مقدار معتبر بین ۱ تا ۲۰۰۰۰ وارد کنید.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(
        CalorieTargets(
          trainingDayCalories: int.parse(
            westernDigits(_trainingController.text),
          ),
          restDayCalories: int.parse(westernDigits(_restController.text)),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = 'ذخیره هدف‌ها ممکن نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _TargetField(
            controller: _trainingController,
            label: 'هدف کالری روز تمرینی',
            icon: Icons.fitness_center,
            validator: _validate,
          ),
          const SizedBox(height: 16),
          _TargetField(
            controller: _restController,
            label: 'هدف کالری روز غیرتمرینی',
            icon: Icons.self_improvement,
            validator: _validate,
          ),
          const SizedBox(height: 24),
          if (_saveError != null) ...[
            Text(
              _saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'در حال ذخیره...' : widget.buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetField extends StatelessWidget {
  const _TargetField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[-0-9۰-۹٠-٩]')),
    ],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixText: 'کالری',
    ),
    validator: validator,
  );
}
