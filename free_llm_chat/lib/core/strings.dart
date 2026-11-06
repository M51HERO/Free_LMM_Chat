import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/settings_controller.dart';
import 'errors.dart';

// Placeholders look like {name} and are filled by trf()/trLangF().
// Keys whose text contains a literal dollar sign use raw strings (r'...').

const _en = <String, String>{
  'appTitle': 'Free LLM Chat',
  'newChat': 'New chat',
  'settings': 'Settings',
  'history': 'History',
  'noChats': 'No chats yet',
  'emptyTitle': 'How can I help you today?',
  'hint': 'Type a message…',
  'send': 'Send',
  'stop': 'Stop',
  'copy': 'Copy',
  'copied': 'Copied',
  'delete': 'Delete',
  'cancel': 'Cancel',
  'deleteQ': 'Delete this chat?',
  'dismiss': 'Dismiss',
  'save': 'Save',
  'saved': 'Saved',
  'language': 'Language',
  'theme': 'Theme',
  'system': 'System',
  'light': 'Light',
  'dark': 'Dark',
  'regenerate': 'Regenerate',
  'edit': 'Edit',
  'retry': 'Retry',
  'gotIt': 'Got it',
  // Manifest connection
  'manifestSection': 'Manifest connection',
  'manifestIntro': 'Manifest is the only backend. It routes each request and handles fallbacks itself.',
  'presetSelfHosted': 'Self-hosted',
  'presetCloud': 'Manifest Cloud',
  'baseUrl': 'Base URL',
  'baseUrlHint': 'With or without /v1. Self-hosted: http://localhost:2099. Cloud: copy the URL from the "Set up agent" dialog if it differs.',
  'androidLocalhost': 'On Android, localhost is the phone itself. Use your PC\'s LAN IP, for example http://192.168.1.20:2099.',
  'agentKey': 'Manifest agent key',
  'keyHint': 'Starts with mnfst_',
  'urlEmpty': 'Enter the Manifest base URL.',
  'urlInvalid': 'This is not a valid http(s) URL.',
  'urlCleartext': 'Plain http:// is only accepted for localhost and LAN addresses. Use https:// for other hosts.',
  'keyBadPrefix': 'An agent key starts with mnfst_.',
  'testConnection': 'Test connection',
  'testing': 'Testing…',
  'testOk': 'Connected. {total} models: {free} free or covered by a subscription, {paid} paid, {unknown} unknown.',
  'testNoModels': 'No models are listed. Connect a provider in Manifest first.',
  // Models
  'modelLabel': 'Model',
  'modelAutoSub': 'auto: Manifest chooses the model',
  'pickModel': 'Choose a model',
  'searchModels': 'Search models',
  'refreshModels': 'Refresh models',
  'modelsStatus': '{free} free/subscription · {paid} paid · {unknown} unknown',
  'modelsUnavailable': 'The model list could not be loaded, so every price is unknown.',
  'modelsNotConfigured': 'Add the agent key in Settings to load the models.',
  'noModelsMatch': 'No models match.',
  'priceFree': 'no per-token charge',
  'priceUnknownShort': 'price unknown',
  // Paid-model warning
  'warnPaid': 'Warn about paid models',
  'warnPaidHint': 'Asks before sending to a paid or price-unknown model and warns about auto routing. Reply badges are always shown.',
  'warnOffTitle': 'Turn off paid-model warnings?',
  'warnOffBody': 'You will no longer be asked before a paid or price-unknown model is used, and the auto-routing notice disappears. Replies still show a badge, but you could be charged without a prompt.',
  'turnOff': 'Turn off',
  'keepOn': 'Keep on',
  'paidTitle': 'This model is paid',
  'unknownTitle': 'Price unknown: may be paid',
  'paidBody': 'Manifest lists it at {price}.',
  'unknownBody': 'Manifest did not report a price for this model, so it may cost money.',
  'unknownBodyNoList': 'The price list could not be loaded, so this model may cost money.',
  'priceFmt': r'${in} in / ${out} out per 1M tokens',
  'sendOnce': 'Send once',
  'switchAutoSend': 'Switch to auto & send',
  'autoNotice': 'Auto routing may use a paid model. Configure free-only tiers/fallbacks and a hard spending cap per key in Manifest.',
  'autoNoticeCounts': '{paid} paid and {unknown} price-unknown of {total} models.',
  'autoNoticeNoList': 'The price list could not be loaded, so all prices are unknown.',
  'badgeFree': 'Free or covered by a subscription',
  'badgePaid': 'Paid',
  'badgeUnknown': 'Price unknown (may be paid)',
  'badgeUnknownNoList': 'Price unknown: list unavailable (may be paid)',
  'badgeAmbiguous': 'Price unclear: several routes match (may be paid)',
  'badgeServedUnknown': 'Served model unknown',
  'badgeManifestSelf': 'Answered by Manifest itself (no model called)',
  'fellBackFrom': 'Fell back from',
  'estimatedCost': r'Estimated cost ≈ ${cost} (estimate only)',
  // One-time migration notice
  'legacyTitle': 'Old provider keys are no longer used',
  'legacyBody': 'This version talks only to Manifest. {n} saved key(s) for other providers are not used any more and will now be deleted from this device. Put those provider keys in Manifest instead. Your Manifest URL and key were kept.',
  // Errors
  'err_missingKey': 'No Manifest agent key. Add it in Settings.',
  'err_notConfigured': 'The Manifest base URL is missing or invalid. Check Settings.',
  'err_invalidKey': 'Manifest rejected the key (401). Check the agent key in Settings.',
  'err_rateLimit': 'Rate limit reached (429). Wait a bit and try again.',
  'err_paymentRequired': 'Payment or quota problem (402): your Manifest plan or an upstream provider\'s billing/quota. Check it in Manifest.',
  'err_spendLimit': 'Your Manifest spending limit was reached, so nothing was sent to a model. Raise it or wait for the period to end in Manifest.',
  'err_modelNotAvailable': 'This model is not available for this key (provider not connected or not enabled). Pick another model or use auto.',
  'err_fallbackExhausted': 'Every model in Manifest\'s fallback chain failed. Check your providers and routing in Manifest.',
  'err_connectionRefused': 'Cannot connect: Manifest is not running at this address. Start it (docker compose up -d) and check the base URL and port. On Android, use the PC\'s LAN IP, not localhost.',
  'err_network': 'Network error. Check your connection and the base URL.',
  'err_timeout': 'The connection timed out. Try again.',
  'err_server': 'Manifest or the provider returned an error. Try again later.',
  'err_badRequest': 'Request rejected. Check the model ID and base URL.',
  'err_unknown': 'Unexpected error.',
};

const _ar = <String, String>{
  'appTitle': 'دردشة النماذج المجانية',
  'newChat': 'محادثة جديدة',
  'settings': 'الإعدادات',
  'history': 'السجل',
  'noChats': 'لا توجد محادثات بعد',
  'emptyTitle': 'كيف أقدر أساعدك اليوم؟',
  'hint': 'اكتب رسالتك…',
  'send': 'إرسال',
  'stop': 'إيقاف',
  'copy': 'نسخ',
  'copied': 'تم النسخ',
  'delete': 'حذف',
  'cancel': 'إلغاء',
  'deleteQ': 'حذف هذه المحادثة؟',
  'dismiss': 'إغلاق',
  'save': 'حفظ',
  'saved': 'تم الحفظ',
  'language': 'اللغة',
  'theme': 'المظهر',
  'system': 'النظام',
  'light': 'فاتح',
  'dark': 'داكن',
  'regenerate': 'إعادة توليد',
  'edit': 'تعديل',
  'retry': 'إعادة المحاولة',
  'gotIt': 'فهمت',
  // اتصال Manifest
  'manifestSection': 'اتصال Manifest',
  'manifestIntro': 'Manifest هو الخلفية الوحيدة للتطبيق: يوجّه كل طلب ويتولى التبديل بين النماذج بنفسه.',
  'presetSelfHosted': 'مستضاف ذاتيًا',
  'presetCloud': 'Manifest Cloud',
  'baseUrl': 'عنوان الخدمة Base URL',
  'baseUrlHint': 'مع /v1 أو بدونها. المستضاف ذاتيًا: http://localhost:2099. السحابة: انسخ العنوان من نافذة "Set up agent" إن اختلف.',
  'androidLocalhost': 'على أندرويد، localhost يعني الهاتف نفسه. استخدم عنوان الحاسوب في الشبكة المحلية، مثل http://192.168.1.20:2099.',
  'agentKey': 'مفتاح وكيل Manifest',
  'keyHint': 'يبدأ بـ mnfst_',
  'urlEmpty': 'أدخل عنوان Manifest.',
  'urlInvalid': 'هذا ليس عنوان http(s) صالحًا.',
  'urlCleartext': 'العنوان http:// العادي مقبول فقط لـ localhost وعناوين الشبكة المحلية. استخدم https:// لغيرها.',
  'keyBadPrefix': 'مفتاح الوكيل يبدأ بـ mnfst_.',
  'testConnection': 'اختبار الاتصال',
  'testing': 'جارٍ الاختبار…',
  'testOk': 'تم الاتصال. {total} نموذج: {free} مجاني أو ضمن اشتراك، {paid} مدفوع، {unknown} غير معروف.',
  'testNoModels': 'لا توجد نماذج في القائمة. اربط مزوّدًا داخل Manifest أولًا.',
  // النماذج
  'modelLabel': 'النموذج',
  'modelAutoSub': 'auto: Manifest يختار النموذج',
  'pickModel': 'اختر نموذجًا',
  'searchModels': 'ابحث في النماذج',
  'refreshModels': 'تحديث النماذج',
  'modelsStatus': '{free} مجاني/اشتراك · {paid} مدفوع · {unknown} غير معروف',
  'modelsUnavailable': 'تعذّر تحميل قائمة النماذج، لذلك كل الأسعار غير معروفة.',
  'modelsNotConfigured': 'أضِف مفتاح الوكيل من الإعدادات لتحميل النماذج.',
  'noModelsMatch': 'لا نماذج مطابقة.',
  'priceFree': 'بلا رسوم لكل توكن',
  'priceUnknownShort': 'السعر غير معروف',
  // تنبيه النماذج المدفوعة
  'warnPaid': 'تنبيه عند النماذج المدفوعة',
  'warnPaidHint': 'يسأل قبل الإرسال إلى نموذج مدفوع أو غير معروف السعر، وينبّه عند التوجيه التلقائي. شارات الردود تظهر دائمًا.',
  'warnOffTitle': 'إيقاف تنبيهات النماذج المدفوعة؟',
  'warnOffBody': 'لن يُطلب منك التأكيد قبل استخدام نموذج مدفوع أو غير معروف السعر، وسيختفي تنبيه التوجيه التلقائي. ستبقى الشارة تظهر على الردود، لكن قد تُحاسَب دون سؤال.',
  'turnOff': 'إيقاف',
  'keepOn': 'إبقاء التنبيه',
  'paidTitle': 'هذا النموذج مدفوع',
  'unknownTitle': 'السعر غير معروف: قد يكون مدفوعًا',
  'paidBody': 'سعره في Manifest: {price}.',
  'unknownBody': 'لم يُبلِغ Manifest عن سعر هذا النموذج، لذلك قد يكلّف مالًا.',
  'unknownBodyNoList': 'تعذّر تحميل قائمة الأسعار، لذلك قد يكلّف هذا النموذج مالًا.',
  'priceFmt': r'الإدخال ${in} / الإخراج ${out} لكل مليون توكن',
  'sendOnce': 'إرسال مرة واحدة',
  'switchAutoSend': 'التبديل إلى auto وإرسال',
  'autoNotice': 'التوجيه التلقائي قد يستخدم نموذجًا مدفوعًا. اضبط في Manifest طبقات وبدائل مجانية فقط، وحدًّا صارمًا للإنفاق لكل مفتاح.',
  'autoNoticeCounts': '{paid} مدفوع و{unknown} غير معروف السعر من أصل {total} نموذج.',
  'autoNoticeNoList': 'تعذّر تحميل قائمة الأسعار، لذلك كل الأسعار غير معروفة.',
  'badgeFree': 'مجاني أو ضمن اشتراك',
  'badgePaid': 'مدفوع',
  'badgeUnknown': 'السعر غير معروف (قد يكون مدفوعًا)',
  'badgeUnknownNoList': 'السعر غير معروف: القائمة غير متاحة (قد يكون مدفوعًا)',
  'badgeAmbiguous': 'السعر غير واضح: عدة مسارات مطابقة (قد يكون مدفوعًا)',
  'badgeServedUnknown': 'النموذج الذي ردّ غير معروف',
  'badgeManifestSelf': 'ردّ Manifest بنفسه (دون استدعاء نموذج)',
  'fellBackFrom': 'تم التحويل من',
  'estimatedCost': r'التكلفة التقديرية ≈ ${cost} (تقدير فقط)',
  // إشعار الترحيل لمرة واحدة
  'legacyTitle': 'مفاتيح المزوّدين القدامى لم تعد تُستخدم',
  'legacyBody': 'هذا الإصدار يتصل بـ Manifest فقط. {n} مفتاح محفوظ لمزوّدين آخرين لم يعد مستخدمًا وسيُحذف الآن من هذا الجهاز. ضع مفاتيح المزوّدين داخل Manifest بدلًا منها. تم الاحتفاظ بعنوان Manifest ومفتاحه.',
  // الأخطاء
  'err_missingKey': 'لا يوجد مفتاح وكيل Manifest. أضِفه من الإعدادات.',
  'err_notConfigured': 'عنوان Manifest ناقص أو غير صالح. راجع الإعدادات.',
  'err_invalidKey': 'رفض Manifest المفتاح (401). تحقق من مفتاح الوكيل في الإعدادات.',
  'err_rateLimit': 'تم تجاوز حد الطلبات (429). انتظر قليلًا ثم حاول مجددًا.',
  'err_paymentRequired': 'مشكلة دفع أو حصة (402): خطة Manifest أو فوترة/حصة مزوّد خلفي. تحقق منها في Manifest.',
  'err_spendLimit': 'تم بلوغ حد الإنفاق في Manifest، لذلك لم يُرسل شيء إلى أي نموذج. ارفع الحد أو انتظر انتهاء الفترة في Manifest.',
  'err_modelNotAvailable': 'هذا النموذج غير متاح لهذا المفتاح (المزوّد غير مربوط أو غير مفعّل). اختر نموذجًا آخر أو استخدم auto.',
  'err_fallbackExhausted': 'فشلت كل النماذج في سلسلة البدائل في Manifest. تحقق من المزوّدين والتوجيه داخل Manifest.',
  'err_connectionRefused': 'تعذّر الاتصال: Manifest غير شغّال على هذا العنوان. شغّله (docker compose up -d) وتحقق من العنوان والمنفذ. على أندرويد استخدم عنوان الحاسوب في الشبكة المحلية بدل localhost.',
  'err_network': 'خطأ في الشبكة. تحقق من الاتصال ومن عنوان الخدمة.',
  'err_timeout': 'انتهت مهلة الاتصال. حاول مرة أخرى.',
  'err_server': 'أعاد Manifest أو المزوّد خطأ. حاول لاحقًا.',
  'err_badRequest': 'تم رفض الطلب. تحقق من معرّف النموذج والعنوان.',
  'err_unknown': 'حدث خطأ غير متوقع.',
};

/// The raw string table of a language (used by the translation tests).
Map<String, String> stringTable(String lang) => lang == 'ar' ? _ar : _en;

/// Plain lookup by language code (usable after an `await`, without a BuildContext).
String trLang(String lang, String key) => (lang == 'ar' ? _ar : _en)[key] ?? key;

/// Lookup + `{name}` placeholders.
String trLangF(String lang, String key, Map<String, String> args) {
  var s = trLang(lang, key);
  args.forEach((k, v) {
    s = s.replaceAll('{$k}', v);
  });
  return s;
}

const _detailKinds = {
  ErrorKind.server,
  ErrorKind.badRequest,
  ErrorKind.unknown,
  ErrorKind.paymentRequired,
  ErrorKind.spendLimit,
  ErrorKind.modelNotAvailable,
  ErrorKind.fallbackExhausted,
};

/// Friendly message, plus the server's own text for the kinds where it helps.
String errorTextFor(String lang, ApiException e) {
  final base = trLang(lang, 'err_${e.kind.name}');
  final showDetail = e.detail != null && _detailKinds.contains(e.kind);
  return showDetail ? '$base\n${e.detail}' : base;
}

extension Tr on BuildContext {
  /// Translate and rebuild when the language changes (use inside build).
  String tr(String key) => trLang(watch<SettingsController>().lang, key);

  /// Translate with {placeholders} and rebuild when the language changes (use inside build).
  String trf(String key, Map<String, String> args) =>
      trLangF(watch<SettingsController>().lang, key, args);

  /// Translate without subscribing (use inside callbacks).
  String trNow(String key) => trLang(read<SettingsController>().lang, key);

  /// Error text; rebuilds when the language changes (use inside build).
  String errorText(ApiException e) => errorTextFor(watch<SettingsController>().lang, e);
}

final _arabicChar = RegExp(r'[\u0600-\u06FF\u0750-\u077F]');
final _latinChar = RegExp(r'[A-Za-z]');

/// Direction of a text block based on its first strong character.
TextDirection? directionOf(String s) {
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (_arabicChar.hasMatch(c)) return TextDirection.rtl;
    if (_latinChar.hasMatch(c)) return TextDirection.ltr;
  }
  return null;
}
