import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/services/first_owner_bootstrap_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class RegisterUserScreen extends ConsumerStatefulWidget {
  const RegisterUserScreen({super.key});

  @override
  ConsumerState<RegisterUserScreen> createState() => _RegisterUserScreenState();
}

class _RegisterUserScreenState extends ConsumerState<RegisterUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _workshopNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _workshopAddressController =
      TextEditingController();
  final TextEditingController _townController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _selectedCountry;
  String? _selectedProvince;

  XFile? _logoImage;
  bool _isLoading = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final List<String> countries = ['فلسطين', 'الأردن', 'مصر', 'سوريا'];
  final Map<String, List<String>> provinces = {
    'فلسطين': ['الضفة الغربية', 'قطاع غزة'],
    'الأردن': ['عمان', 'إربد'],
    'مصر': ['القاهرة', 'الإسكندرية'],
    'سوريا': ['دمشق', 'حلب'],
  };

  Future<void> _pickLogoImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null && mounted) {
      setState(() {
        _logoImage = pickedFile;
      });
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showMessage('كلمة المرور وتأكيدها غير متطابقين');
      return;
    }

    if (_selectedCountry == null || _selectedProvince == null) {
      _showMessage('يرجى اختيار البلد والمنطقة');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userService = ref.read(userServiceProvider);

      if (await userService.hasAnyUsers()) {
        _showMessage('تم إعداد مالك المنشأة مسبقًا.');
        if (mounted) {
          AppRoutes.navigatorKey.currentState?.pushReplacementNamed('/login');
        }
        return;
      }

      final result = await userService.bootstrapFirstOwner(
        FirstOwnerBootstrapRequest(
          ownerName: _usernameController.text.trim(),
          password: _passwordController.text,
          workshopName: _workshopNameController.text.trim(),
          workshopAddress: _workshopAddressController.text.trim(),
          country: _selectedCountry!,
          province: _selectedProvince!,
          city: _townController.text.trim(),
          street: _streetController.text.trim(),
          phone: _phoneController.text.trim(),
          logoPath: _logoImage?.path,
        ),
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تم إنشاء مالك المنشأة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'احفظ رمز الاستعادة في مكان آمن. سيظهر لك الآن مرة واحدة فقط.',
              ),
              const SizedBox(height: 14),
              SelectableText(
                result.recoveryCode,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('حفظته'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      _showMessage('تم إنشاء حساب مالك المنشأة بنجاح', isError: false);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        AppRoutes.navigatorKey.currentState?.pushReplacementNamed('/login');
      }
    } catch (e) {
      _showMessage('حدث خطأ: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey.shade100,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      suffixIcon: suffixIcon,
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Y',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Arial',
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 16, height: 1.3, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _workshopNameController.dispose();
    _usernameController.dispose();
    _workshopAddressController.dispose();
    _townController.dispose();
    _streetController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 920),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 22,
                      offset: Offset(0, 10)),
                ],
              ),
              child: Row(
                children: [
                  // Right Side: Form Fields
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 36),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Title Row with icon button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'إعداد حساب مالك المنشأة',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.start,
                                ),
                                IconButton(
                                  onPressed: () {
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop(false);
                                    } else {
                                      AppRoutes.navigatorKey.currentState
                                          ?.pushReplacementNamed('/login');
                                    }
                                  },
                                  icon: const Icon(Icons.login),
                                  tooltip: 'العودة إلى تسجيل الدخول',
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            // Workshop and Username Row
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _workshopNameController,
                                    decoration: InputDecoration(
                                      labelText: 'اسم الورشة',
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 18),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _logoImage == null
                                              ? Icons.image_outlined
                                              : Icons.check_circle,
                                          color: _logoImage == null
                                              ? Colors.grey
                                              : AppColors.primary,
                                        ),
                                        tooltip: 'رفع شعار الورشة (اختياري)',
                                        onPressed: _pickLogoImage,
                                      ),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'مطلوب'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: TextFormField(
                                    controller: _usernameController,
                                    decoration:
                                        _inputDecoration('اسم المستخدم'),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'مطلوب'
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Country and Province Row with type-safe DropdownMenuItems
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    decoration: _inputDecoration('البلد'),
                                    value: _selectedCountry,
                                    items: countries
                                        .map<DropdownMenuItem<String>>(
                                          (c) => DropdownMenuItem<String>(
                                            value: c,
                                            child: Text(c),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedCountry = val;
                                        _selectedProvince = null;
                                      });
                                    },
                                    validator: (v) =>
                                        v == null ? 'يرجى الاختيار' : null,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    decoration: _inputDecoration('المنطقة'),
                                    value: _selectedProvince,
                                    items: (_selectedCountry != null
                                            ? provinces[_selectedCountry]!
                                            : [])
                                        .map<DropdownMenuItem<String>>(
                                          (p) => DropdownMenuItem<String>(
                                            value: p,
                                            child: Text(p),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedProvince = val;
                                      });
                                    },
                                    validator: (v) =>
                                        v == null ? 'يرجى الاختيار' : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            // Town and Street Row
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _townController,
                                    decoration: _inputDecoration('المحافظة'),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'مطلوب'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: TextFormField(
                                    controller: _streetController,
                                    decoration: _inputDecoration('البلدة'),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'مطلوب'
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            // Phone Number
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: _inputDecoration('رقم الهاتف'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'مطلوب'
                                  : null,
                            ),
                            const SizedBox(height: 18),
                            // Password with show/hide toggle
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: _inputDecoration(
                                'كلمة المرور',
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                              validator: (v) =>
                                  UserService.validatePasswordPolicy(v ?? ''),
                            ),
                            const SizedBox(height: 18),
                            // Confirm Password with show/hide toggle
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              decoration: _inputDecoration(
                                'تأكيد كلمة المرور',
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirmPassword =
                                          !_obscureConfirmPassword;
                                    });
                                  },
                                ),
                              ),
                              validator: (v) {
                                if (v != _passwordController.text) {
                                  return 'كلمتا المرور غير متطابقتين';
                                }
                                return UserService.validatePasswordPolicy(
                                  v ?? '',
                                );
                              },
                            ),
                            const SizedBox(height: 26),
                            // Register button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                textStyle: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text('إنشاء حساب مالك المنشأة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Left side: Logo and features with two columns
                  Expanded(
                    flex: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 40),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(22),
                          bottomLeft: Radius.circular(22),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 160,
                            width: 220,
                            child: Image.asset('assets/logo/logo.png',
                                fit: BoxFit.contain),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            'الأول في إدارة ورش دهان السيارات',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // First column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildBulletPoint('مبيعات التأمين'),
                                    _buildBulletPoint('مبيعات الأفراد'),
                                    _buildBulletPoint('الحسابات العامة'),
                                    _buildBulletPoint('العملاء والموردين'),
                                    _buildBulletPoint('شؤون الموظفين'),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 40),
                              // Second column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildBulletPoint('تتبع المخزون'),
                                    _buildBulletPoint('المصروفات'),
                                    _buildBulletPoint('المواد الخام'),
                                    _buildBulletPoint('قطع السيارات'),
                                    _buildBulletPoint('ملفات التأمين'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
