import 'package:flutter/material.dart';
import 'yalla_button.dart';

class YallaButtons {
  static YallaButton save(VoidCallback onPressed) => YallaButton(
        text: 'حفظ',
        icon: Icons.save,
        onPressed: onPressed,
      );

  static YallaButton add(VoidCallback onPressed) => YallaButton(
        text: 'إضافة',
        icon: Icons.add,
        onPressed: onPressed,
      );

  static YallaButton edit(VoidCallback onPressed) => YallaButton(
        text: 'تعديل',
        icon: Icons.edit,
        onPressed: onPressed,
      );

  static YallaButton delete(VoidCallback onPressed) => YallaButton(
        text: 'حذف',
        icon: Icons.delete,
        onPressed: onPressed,
        isDanger: true,
      );

  static YallaButton view(VoidCallback onPressed) => YallaButton(
        text: 'عرض',
        icon: Icons.visibility,
        onPressed: onPressed,
      );

  static YallaButton print(VoidCallback onPressed) => YallaButton(
        text: 'طباعة',
        icon: Icons.print,
        onPressed: onPressed,
      );

  static YallaButton exportExcel(VoidCallback onPressed) => YallaButton(
        text: 'تصدير Excel',
        icon: Icons.table_view,
        onPressed: onPressed,
      );

  static YallaButton share(VoidCallback onPressed) => YallaButton(
        text: 'مشاركة',
        icon: Icons.share,
        onPressed: onPressed,
      );

  static YallaButton newPayment(VoidCallback onPressed) => YallaButton(
        text: 'دفعة جديدة',
        icon: Icons.payment,
        onPressed: onPressed,
      );

  static YallaButton uploadImage(VoidCallback onPressed) => YallaButton(
        text: 'تحميل صورة',
        icon: Icons.camera_alt,
        onPressed: onPressed,
      );
}
