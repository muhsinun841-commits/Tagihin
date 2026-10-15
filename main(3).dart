import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TagihinApp());
}

const navy = Color(0xFF12315A);
const blue = Color(0xFF246BCE);
const green = Color(0xFF15966A);
const orange = Color(0xFFF39A25);
const bg = Color(0xFFF3F6FA);

String rupiah(num n) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0).format(n);
String tanggal(DateTime? d) => d == null ? '-' : DateFormat('dd MMM yyyy', 'id_ID').format(d);
DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int || value is double) {
    try {
      return DateTime(1899, 12, 30).add(Duration(days: (value as num).round()));
    } catch (_) {}
  }
  final s = value.toString().trim();
  for (final f in ['dd/MM/yyyy', 'd/M/yyyy', 'yyyy-MM-dd', 'dd-MM-yyyy', 'd-M-yyyy', 'MM/dd/yyyy']) {
    try { return DateFormat(f).parseStrict(s); } catch (_) {}
  }
  return DateTime.tryParse(s);
}
String cleanPhone(String input) {
  var p = input.replaceAll(RegExp(r'[^0-9+]'), '');
  if (p.startsWith('+')) p = p.substring(1);
  if (p.startsWith('0')) p = '62${p.substring(1)}';
  if (p.startsWith('8')) p = '62$p';
  return p;
}
double parseMoney(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  var s = v.toString().trim().replaceAll(RegExp(r'[^0-9,.-]'), '');
  if (s.contains('.') && s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (s.contains(',') && !s.contains('.')) {
    s = s.replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s) ?? 0;
}

class Loan {
  String id;
  String memberId;
  String product;
  DateTime dueDate;
  double amount;
  double paid;
  String period;
  String status;
  Loan({required this.id, required this.memberId, required this.product, required this.dueDate,
    required this.amount, this.paid = 0, required this.period, this.status = 'Belum lunas'});
  double get remaining => (amount - paid).clamp(0, double.infinity);
  Map<String, dynamic> toJson() => {'id':id,'memberId':memberId,'product':product,'dueDate':dueDate.toIso8601String(),'amount':amount,'paid':paid,'period':period,'status':status};
  factory Loan.fromJson(Map<String,dynamic> j) => Loan(
    id: j['id'] ?? '', memberId: j['memberId'] ?? '', product: j['product'] ?? 'Angsuran',
    dueDate: DateTime.tryParse(j['dueDate'] ?? '') ?? DateTime.now(),
    amount: (j['amount'] as num? ?? 0).toDouble(), paid: (j['paid'] as num? ?? 0).toDouble(),
    period: j['period'] ?? DateFormat('yyyy-MM').format(DateTime.now()), status: j['status'] ?? 'Belum lunas');
}

class Member {
  String id, name, address, phone, marketing;
  Member({required this.id, required this.name, required this.address, required this.phone, required this.marketing});
  Map<String,dynamic> toJson() => {'id':id,'name':name,'address':address,'phone':phone,'marketing':marketing};
  factory Member.fromJson(Map<String,dynamic> j) => Member(id:j['id']??'',name:j['name']??'',address:j['address']??'',phone:j['phone']??'',marketing:j['marketing']??'Saya');
}

class CollectionLog {
  String id, loanId, memberId, result, note;
  DateTime createdAt;
  double amountPaid;
  CollectionLog({required this.id, required this.loanId, required this.memberId, required this.result, required this.note, required this.createdAt, required this.amountPaid});
  Map<String,dynamic> toJson() => {'id':id,'loanId':loanId,'memberId':memberId,'result':result,'note':note,'createdAt':createdAt.toIso8601String(),'amountPaid':amountPaid};
  factory CollectionLog.fromJson(Map<String,dynamic> j) => CollectionLog(id:j['id']??'',loanId:j['loanId']??'',memberId:j['memberId']??'',result:j['result']??'',note:j['note']??'',createdAt:DateTime.tryParse(j['createdAt']??'')??DateTime.now(),amountPaid:(j['amountPaid'] as num? ?? 0).toDouble());
}

class Store extends ChangeNotifier {
  List<Member> members = [];
  List<Loan> loans = [];
  List<CollectionLog> logs = [];
  String marketingName = 'Marketing';
  bool loaded = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    marketingName = p.getString('marketingName') ?? 'Marketing';
    members = (jsonDecode(p.getString('members') ?? '[]') as List).map((e)=>Member.fromJson(Map<String,dynamic>.from(e))).toList();
    loans = (jsonDecode(p.getString('loans') ?? '[]') as List).map((e)=>Loan.fromJson(Map<String,dynamic>.from(e))).toList();
    logs = (jsonDecode(p.getString('logs') ?? '[]') as List).map((e)=>CollectionLog.fromJson(Map<String,dynamic>.from(e))).toList();
    loaded = true; notifyListeners();
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('marketingName', marketingName);
    await p.setString('members', jsonEncode(members.map((e)=>e.toJson()).toList()));
    await p.setString('loans', jsonEncode(loans.map((e)=>e.toJson()).toList()));
    await p.setString('logs', jsonEncode(logs.map((e)=>e.toJson()).toList()));
    notifyListeners();
  }
  Member? member(String id) { for(final m in members) { if(m.id==id) return m; } return null; }
  Loan? loan(String id) { for(final l in loans) { if(l.id==id) return l; } return null; }
  Future<void> addLog(Loan l, String result, double paid, String note) async {
    if (paid > 0) { l.paid += paid; if(l.paid >= l.amount) l.status = 'Lunas'; }
    logs.insert(0, CollectionLog(id:DateTime.now().microsecondsSinceEpoch.toString(),loanId:l.id,memberId:l.memberId,result:result,note:note,createdAt:DateTime.now(),amountPaid:paid));
    await save();
  }
  Future<void> importExcel(Uint8List bytes, String period) async {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) throw Exception('File Excel tidak memiliki sheet.');
    final sheet = book.tables.values.first!;
    if (sheet.rows.length < 2) throw Exception('Data Excel kosong.');
    final headers = sheet.rows.first.map((c)=>(c?.value?.toString() ?? '').toLowerCase().trim()).toList();
    int find(List<String> keys) => headers.indexWhere((h)=>keys.any((k)=>h.contains(k)));
    final iName=find(['nama anggota','nama nasabah','nama','anggota']);
    final iAddr=find(['alamat']);
    final iPhone=find(['no hp','nomor hp','telepon','no telp','whatsapp','hp']);
    final iDue=find(['jatuh tempo','tgl jatuh tempo','tanggal angsuran','tanggal tagihan','tgl tempo','tempo']);
    final iAmount=find(['nominal tagihan','jumlah tagihan','angsuran','tagihan','nominal']);
    final iMemberId=find(['id anggota','kode anggota','no anggota','nomor anggota']);
    final iLoanId=find(['id pembiayaan','kode pembiayaan','no pembiayaan','nomor pembiayaan','id tagihan']);
    final iProduct=find(['jenis pembiayaan','produk','jenis tagihan','pembiayaan']);
    final iMarketing=find(['marketing','petugas']);
    if(iName<0 || iDue<0 || iAmount<0) throw Exception('Kolom wajib belum ditemukan. Minimal perlu Nama, Jatuh Tempo, dan Tagihan. Periksa judul kolom Excel.');
    String val(List<Data?> row, int i) => i<0 || i>=row.length ? '' : (row[i]?.value?.toString().trim() ?? '');
    int imported=0, skipped=0;
    for (var r=1; r<sheet.rows.length; r++) {
      final row=sheet.rows[r];
      final name=val(row,iName);
      if(name.isEmpty) { skipped++; continue; }
      final due=parseDate(iDue<row.length ? row[iDue]?.value : null);
      if(due==null) { skipped++; continue; }
      final rawMemberId=val(row,iMemberId);
      final memberId=rawMemberId.isNotEmpty ? rawMemberId : 'M-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}-${val(row,iPhone).replaceAll(RegExp(r'[^0-9]'), '')}';
      var m=member(memberId);
      if(m==null) {
        m=Member(id:memberId,name:name,address:val(row,iAddr),phone:val(row,iPhone),marketing:val(row,iMarketing).isEmpty?marketingName:val(row,iMarketing));
        members.add(m);
      } else {
        m.name=name; m.address=val(row,iAddr); m.phone=val(row,iPhone);
        if(val(row,iMarketing).isNotEmpty) m.marketing=val(row,iMarketing);
      }
      final loanIdRaw=val(row,iLoanId);
      final product=val(row,iProduct).isEmpty?'Angsuran':val(row,iProduct);
      final loanId=loanIdRaw.isNotEmpty ? '$loanIdRaw-$period' : '${memberId}-${product.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}-${DateFormat('yyyyMMdd').format(due)}-$period';
      final existing=loans.indexWhere((l)=>l.id==loanId);
      final amount=parseMoney(iAmount<row.length?row[iAmount]?.value:null);
      if(existing>=0) {
        final old=loans[existing];
        // Do not reset payment already recorded for this period.
        old.product=product; old.dueDate=due; old.amount=amount;
        old.status=old.paid>=old.amount?'Lunas':'Belum lunas';
      } else {
        loans.add(Loan(id:loanId,memberId:memberId,product:product,dueDate:due,amount:amount,period:period));
      }
      imported++;
    }
    await save();
    if(imported==0) throw Exception('Tidak ada baris valid yang berhasil diimpor.');
  }
}

final store = Store();

class TagihinApp extends StatelessWidget {
  const TagihinApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title:'TAGIHIN', debugShowCheckedModeBanner:false,
    theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:blue,primary:navy),scaffoldBackgroundColor:bg,
      appBarTheme:const AppBarTheme(backgroundColor:bg,foregroundColor:navy,elevation:0,centerTitle:false),
      cardTheme:CardThemeData(color:Colors.white,elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))),
      inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:bg,border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))),
    home: const BootPage());
}

// Alias kompatibilitas jika file test lama masih menggunakan MyApp.
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const TagihinApp();
}

class BootPage extends StatefulWidget { const BootPage({super.key}); @override State<BootPage> createState()=>_BootPageState(); }
class _BootPageState extends State<BootPage> {
  @override void initState(){super.initState();store.load().then((_){if(mounted)setState((){});});}
  @override Widget build(BuildContext context) => !store.loaded ? const Scaffold(body:Center(child:CircularProgressIndicator())) : const MainPage();
}

class MainPage extends StatefulWidget { const MainPage({super.key}); @override State<MainPage> createState()=>_MainPageState(); }
class _MainPageState extends State<MainPage> {
  int index=0;
  final titles=['Beranda','Jadwal','Anggota','Penagihan','Laporan'];
  @override Widget build(BuildContext context) {
    final pages=[HomePage(onImport:importFile), SchedulePage(), MembersPage(), CollectionPage(), ReportPage()];
    return Scaffold(appBar:AppBar(title:Row(children:[Container(width:38,height:38,decoration:BoxDecoration(color:navy,borderRadius:BorderRadius.circular(12)),child:const Icon(Icons.fact_check_rounded,color:Colors.white)),const SizedBox(width:10),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('TAGIHIN',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1)),Text(titles[index],style:TextStyle(fontSize:12,color:Colors.blueGrey.shade600))])]),
      actions:[IconButton(tooltip:'Pengaturan',onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SettingsPage())),icon:const Icon(Icons.settings_outlined))]),
      body:IndexedStack(index:index,children:pages),
      bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),backgroundColor:Colors.white,indicatorColor:blue.withValues(alpha:.12),
        destinations:const [NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Beranda'),NavigationDestination(icon:Icon(Icons.calendar_month_outlined),selectedIcon:Icon(Icons.calendar_month),label:'Jadwal'),NavigationDestination(icon:Icon(Icons.groups_outlined),selectedIcon:Icon(Icons.groups),label:'Anggota'),NavigationDestination(icon:Icon(Icons.payments_outlined),selectedIcon:Icon(Icons.payments),label:'Penagihan'),NavigationDestination(icon:Icon(Icons.assessment_outlined),selectedIcon:Icon(Icons.assessment),label:'Laporan')]));
  }
  Future<void> importFile() async {
    final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['xlsx','xls'],withData:true);
    if(result==null||result.files.single.bytes==null)return;
    final now=DateTime.now(); final period=DateFormat('yyyy-MM').format(now);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Impor tagihan bulanan'),content:Text('Data akan dicocokkan untuk periode $period. Tagihan periode lain dan riwayat pembayaran tidak dihapus. Lanjutkan?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Impor'))]));
    if(ok!=true)return;
    try { await store.importExcel(result.files.single.bytes!,period); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Impor selesai. Periksa daftar anggota dan tagihan.'))); }
    catch(e){if(mounted)showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Impor belum berhasil'),content:Text('$e'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Tutup'))]));}
  }
}

Widget sectionTitle(String title,{String? trailing,VoidCallback? onTap})=>Padding(padding:const EdgeInsets.fromLTRB(18,18,18,10),child:Row(children:[Expanded(child:Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800,color:navy))),if(trailing!=null)TextButton(onPressed:onTap,child:Text(trailing))]));
Widget emptyState(String text)=>Padding(padding:const EdgeInsets.all(28),child:Center(child:Text(text,textAlign:TextAlign.center,style:TextStyle(color:Colors.blueGrey.shade500))));
Widget moneyText(num n,{double size=16,Color color=navy})=>Text(rupiah(n),style:TextStyle(fontWeight:FontWeight.w800,fontSize:size,color:color));
Member? getMember(String id)=>store.member(id);
List<Loan> get openLoans=>store.loans.where((l)=>l.remaining>0).toList();
List<Loan> get todayLoans=>openLoans.where((l)=>DateUtils.isSameDay(l.dueDate,DateTime.now())).toList();
List<Loan> get overdueLoans=>openLoans.where((l)=>l.dueDate.isBefore(DateTime.now())&&!DateUtils.isSameDay(l.dueDate,DateTime.now())).toList();
double get todayPaid=>store.logs.where((l)=>DateUtils.isSameDay(l.createdAt,DateTime.now())).fold(0.0,(s,l)=>s+l.amountPaid);

class HomePage extends StatelessWidget {
  final VoidCallback onImport; const HomePage({super.key,required this.onImport});
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.only(bottom:24),children:[
    Container(margin:const EdgeInsets.fromLTRB(16,8,16,4),padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[navy,blue]),borderRadius:BorderRadius.circular(22)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Halo, ${store.marketingName} 👋',style:const TextStyle(color:Colors.white70,fontSize:14)),const SizedBox(height:6),const Text('Siap menuntaskan penagihan hari ini?',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w800)),const SizedBox(height:18),
      Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Tagihan jatuh tempo hari ini',style:TextStyle(color:Colors.white70,fontSize:12)),moneyText(todayLoans.fold(0.0,(s,l)=>s+l.remaining),color:Colors.white,size:19)])),Container(width:1,height:44,color:Colors.white24),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Pembayaran hari ini',style:TextStyle(color:Colors.white70,fontSize:12)),moneyText(todayPaid,color:Colors.white,size:19)]))])])),
    Padding(padding:const EdgeInsets.fromLTRB(16,14,16,0),child:Row(children:[Expanded(child:OutlinedButton.icon(onPressed:onImport,icon:const Icon(Icons.upload_file),label:const Text('Import Excel'),style:OutlinedButton.styleFrom(padding:const EdgeInsets.symmetric(vertical:14)))),const SizedBox(width:10),Expanded(child:FilledButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const SettingsPage())),icon:const Icon(Icons.person_outline),label:const Text('Profil'),style:FilledButton.styleFrom(backgroundColor:navy,padding:const EdgeInsets.symmetric(vertical:14))))])),
    sectionTitle('Ringkasan tagihan'),
    Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.65,crossAxisSpacing:10,mainAxisSpacing:10,children:[
      statCard('Anggota', '${store.members.length}', Icons.groups, blue),
      statCard('Tagihan aktif', '${openLoans.length}', Icons.receipt_long, navy),
      statCard('Total tunggakan', rupiah(overdueLoans.fold(0.0,(s,l)=>s+l.remaining)), Icons.warning_amber_rounded, orange),
      statCard('Sudah dibayar hari ini',rupiah(todayPaid),Icons.check_circle_outline,green),
    ])),
    sectionTitle('Prioritas penagihan',trailing:'Lihat jadwal',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const SchedulePage()))),
    ...((todayLoans.isEmpty && overdueLoans.isEmpty)
        ? <Widget>[
            emptyState('Belum ada tagihan jatuh tempo atau terlambat.\nImport file Excel untuk memulai.'),
          ]
        : (overdueLoans + todayLoans)
            .take(6)
            .map<Widget>((loan) => LoanTile(loan: loan))
            .toList()),
    const SizedBox(height:10)
  ]);
}
Widget statCard(String title,String value,IconData icon,Color color)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(18)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Icon(icon,color:color),Text(title,style:TextStyle(color:Colors.blueGrey.shade600,fontSize:12)),FittedBox(fit:BoxFit.scaleDown,alignment:Alignment.centerLeft,child:Text(value,style:const TextStyle(fontWeight:FontWeight.w800,color:navy,fontSize:16)))]));
class LoanTile extends StatelessWidget {
  final Loan loan; const LoanTile({super.key,required this.loan});
  @override Widget build(BuildContext context){final m=getMember(loan.memberId);final late=loan.dueDate.isBefore(DateTime.now())&&!DateUtils.isSameDay(loan.dueDate,DateTime.now());
    return Card(margin:const EdgeInsets.symmetric(horizontal:16,vertical:5),child:ListTile(onTap:()=>showLoanDetail(context,loan),leading:CircleAvatar(backgroundColor:late?orange.withValues(alpha:.15):blue.withValues(alpha:.1),child:Icon(late?Icons.warning_amber:Icons.person_outline,color:late?orange:blue)),title:Text(m?.name??'Anggota',style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('${loan.product} • Jatuh tempo ${tanggal(loan.dueDate)}\\nSisa ${rupiah(loan.remaining)}'),isThreeLine:true,trailing:const Icon(Icons.chevron_right)));}
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  int filter = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final filters = ['Hari ini', '7 hari ke depan', 'Terlambat', 'Semua'];
    final list = openLoans.where((loan) {
      if (filter == 0) return DateUtils.isSameDay(loan.dueDate, now);
      if (filter == 1) {
        final due = DateTime(loan.dueDate.year, loan.dueDate.month, loan.dueDate.day);
        return !due.isBefore(today) && !due.isAfter(today.add(const Duration(days: 7)));
      }
      if (filter == 2) {
        final due = DateTime(loan.dueDate.year, loan.dueDate.month, loan.dueDate.day);
        return due.isBefore(today);
      }
      return true;
    }).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.asMap().entries.map((entry) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: filter == entry.key,
                  onSelected: (_) => setState(() => filter = entry.key),
                ),
              )).toList(),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? emptyState('Tidak ada tagihan pada filter ini.')
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) => LoanTile(loan: list[index]),
                ),
        ),
      ],
    );
  }
}

class MembersPage extends StatefulWidget {const MembersPage({super.key});@override State<MembersPage> createState()=>_MembersPageState();}
class _MembersPageState extends State<MembersPage>{
 String query='';
 @override Widget build(BuildContext context){
   final list=store.members.where((m)=>('${m.name} ${m.address} ${m.phone}').toLowerCase().contains(query.toLowerCase())).toList()..sort((a,b)=>a.name.compareTo(b.name));
   return Column(children:[Padding(padding:const EdgeInsets.all(16),child:TextField(onChanged:(v)=>setState(()=>query=v),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Cari nama, alamat, atau nomor HP'))),
     Expanded(child:list.isEmpty?emptyState('Data anggota belum tersedia.\\nGunakan Import Excel di Beranda.'):ListView.builder(itemCount:list.length,itemBuilder:(c,i){final m=list[i];final loans=store.loans.where((l)=>l.memberId==m.id&&l.remaining>0).toList();return Card(margin:const EdgeInsets.symmetric(horizontal:16,vertical:5),child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFE8F0FC),child:Icon(Icons.person,color:blue)),title:Text(m.name,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('${m.address}\\n${m.phone} • ${loans.length} tagihan aktif'),isThreeLine:true,trailing:const Icon(Icons.chevron_right),onTap:()=>showMemberDetail(context,m)));}))]);
 }
}

class CollectionPage extends StatelessWidget {const CollectionPage({super.key});
 @override Widget build(BuildContext context){
   final list=openLoans..sort((a,b)=>a.dueDate.compareTo(b.dueDate));
   return Column(children:[sectionTitle('Pilih tagihan untuk dicatat'),Expanded(child:list.isEmpty?emptyState('Belum ada tagihan aktif. Import Excel terlebih dahulu.'):ListView(children:list.map((l)=>Card(margin:const EdgeInsets.symmetric(horizontal:16,vertical:5),child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFE5F6EE),child:Icon(Icons.payments_outlined,color:green)),title:Text(getMember(l.memberId)?.name??'Anggota',style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('${l.product} • Sisa ${rupiah(l.remaining)}'),trailing:const Icon(Icons.chevron_right),onTap:()=>showCollectionForm(context,l)))).toList()))]);
 }
}

class ReportPage extends StatefulWidget {const ReportPage({super.key});@override State<ReportPage> createState()=>_ReportPageState();}
class _ReportPageState extends State<ReportPage>{
 final note=TextEditingController(); final follow=TextEditingController();
 @override void dispose(){note.dispose();follow.dispose();super.dispose();}
 @override Widget build(BuildContext context){
   final today=store.logs.where((l)=>DateUtils.isSameDay(l.createdAt,DateTime.now())).toList();
   final paid=today.fold(0.0,(s,l)=>s+l.amountPaid);
   final contacted=today.map((l)=>l.memberId).toSet().length;
   final successful=today.where((l)=>l.amountPaid>0).map((l)=>l.memberId).toSet().length;
   return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,24),children:[
     const Text('Laporan penagihan',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:4),Text('Ringkasan otomatis hari ini • ${tanggal(DateTime.now())}',style:TextStyle(color:Colors.blueGrey.shade600)),
     const SizedBox(height:14),GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.7,crossAxisSpacing:10,mainAxisSpacing:10,children:[statCard('Anggota dicatat','$contacted',Icons.groups,blue),statCard('Ada pembayaran','$successful',Icons.check_circle,green),statCard('Total pembayaran',rupiah(paid),Icons.payments,green),statCard('Catatan penagihan','${today.length}',Icons.edit_note,orange)]),
     const SizedBox(height:18),const Text('Catatan tambahan',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16)),const SizedBox(height:8),
     TextField(controller:note,maxLines:3,decoration:const InputDecoration(hintText:'Kendala atau hasil penting hari ini...')),
     const SizedBox(height:10),TextField(controller:follow,maxLines:2,decoration:const InputDecoration(hintText:'Rencana tindak lanjut...')),
     const SizedBox(height:14),FilledButton.icon(onPressed:()=>exportReport(context,today,paid,contacted,successful,note.text,follow.text),icon:const Icon(Icons.file_download_outlined),label:const Text('Buat & Ekspor Laporan Excel'),style:FilledButton.styleFrom(backgroundColor:navy,padding:const EdgeInsets.all(15))),
     const SizedBox(height:18),const Text('Riwayat penagihan terbaru',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
     if(store.logs.isEmpty)emptyState('Belum ada catatan penagihan.') else ...store.logs.take(10).map((l){final m=getMember(l.memberId);return Card(child:ListTile(leading:const Icon(Icons.history,color:blue),title:Text(m?.name??'Anggota'),subtitle:Text('${l.result} • ${tanggal(l.createdAt)}${l.note.isEmpty?'':'\\n${l.note}'}'),trailing:Text(rupiah(l.amountPaid),style:const TextStyle(fontWeight:FontWeight.w800,color:green))));})
   ]);
 }
}

Future<void> exportReport(BuildContext context,List<CollectionLog> today,double paid,int contacted,int successful,String note,String follow) async {
 try {
  final excel=Excel.createExcel(); final sheet=excel['Laporan'];
  sheet.appendRow([TextCellValue('LAPORAN PENAGIHAN TAGIHIN')]);
  sheet.appendRow([TextCellValue('Tanggal'),TextCellValue(tanggal(DateTime.now()))]);
  sheet.appendRow([TextCellValue('Marketing'),TextCellValue(store.marketingName)]);
  sheet.appendRow([TextCellValue('Anggota tercatat'),IntCellValue(contacted)]);
  sheet.appendRow([TextCellValue('Anggota dengan pembayaran'),IntCellValue(successful)]);
  sheet.appendRow([TextCellValue('Total pembayaran'),DoubleCellValue(paid)]);
  sheet.appendRow([TextCellValue('Kendala'),TextCellValue(note)]);
  sheet.appendRow([TextCellValue('Tindak lanjut'),TextCellValue(follow)]);
  sheet.appendRow([]);
  sheet.appendRow([TextCellValue('Waktu'),TextCellValue('Nama'),TextCellValue('Hasil'),TextCellValue('Pembayaran'),TextCellValue('Catatan')]);
  for(final l in today){sheet.appendRow([TextCellValue(DateFormat('HH:mm').format(l.createdAt)),TextCellValue(getMember(l.memberId)?.name??''),TextCellValue(l.result),DoubleCellValue(l.amountPaid),TextCellValue(l.note)]);}
  final bytes=excel.encode(); if(bytes==null)throw Exception('Gagal membuat file Excel');
  final dir=await getTemporaryDirectory(); final path='${dir.path}/Laporan_TAGIHIN_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
  await File(path).writeAsBytes(bytes,flush:true);
  await Share.shareXFiles([XFile(path)],text:'Laporan penagihan TAGIHIN - ${tanggal(DateTime.now())}');
 } catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Gagal mengekspor laporan: $e')));}
}

class SettingsPage extends StatefulWidget {const SettingsPage({super.key});@override State<SettingsPage> createState()=>_SettingsPageState();}
class _SettingsPageState extends State<SettingsPage>{
 late final TextEditingController name=TextEditingController(text:store.marketingName);
 @override void dispose(){name.dispose();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Pengaturan')),body:ListView(padding:const EdgeInsets.all(16),children:[
   const Text('Profil marketing',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:navy)),const SizedBox(height:10),
   TextField(controller:name,decoration:const InputDecoration(labelText:'Nama marketing',prefixIcon:Icon(Icons.person_outline))),
   const SizedBox(height:12),FilledButton(onPressed:()async{store.marketingName=name.text.trim().isEmpty?'Marketing':name.text.trim();await store.save();if(context.mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Profil disimpan')));Navigator.pop(context);}},child:const Text('Simpan profil')),
   const SizedBox(height:24),const Text('Data dan privasi',style:TextStyle(fontSize:18,fontWeight:FontWeight.w800,color:navy)),const SizedBox(height:8),
   const Text('Data disimpan secara lokal di perangkat ini. Buat cadangan secara berkala. Laporan Excel dapat dibagikan kepada kepala cabang untuk dicocokkan dengan hardfile resmi.'),
   const SizedBox(height:14),OutlinedButton.icon(onPressed:()async{final data={'marketingName':store.marketingName,'members':store.members.map((e)=>e.toJson()).toList(),'loans':store.loans.map((e)=>e.toJson()).toList(),'logs':store.logs.map((e)=>e.toJson()).toList()};final dir=await getTemporaryDirectory();final f=File('${dir.path}/Cadangan_TAGIHIN.json');await f.writeAsString(jsonEncode(data));await Share.shareXFiles([XFile(f.path)],text:'Cadangan data TAGIHIN');},icon:const Icon(Icons.backup_outlined),label:const Text('Bagikan cadangan data')),
   const SizedBox(height:10),const Text('Peringatan: penyimpanan lokal berarti data tidak otomatis tersinkron antar-HP. File Excel impor sebaiknya memiliki ID anggota dan ID pembiayaan yang stabil.',style:TextStyle(color:Colors.deepOrange,fontSize:12))
 ]));
}

Future<void> showMemberDetail(BuildContext context,Member m) async {
 final loans=store.loans.where((l)=>l.memberId==m.id).toList();
 await showModalBottomSheet(context:context,isScrollControlled:true,showDragHandle:true,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(20,8,20,24),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
   Text(m.name,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:navy)),const SizedBox(height:6),Text(m.address),Text(m.phone),const SizedBox(height:16),const Text('Daftar pembiayaan',style:TextStyle(fontWeight:FontWeight.w800,fontSize:16)),
   ...loans.map((l)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(l.product),subtitle:Text('Tempo ${tanggal(l.dueDate)} • ${l.period}'),trailing:Text(rupiah(l.remaining),style:const TextStyle(fontWeight:FontWeight.w800)))),
   const SizedBox(height:8),FilledButton.icon(onPressed:()=>sendWhatsApp(context,m,loans),icon:const Icon(Icons.chat),label:const Text('Buat pesan WhatsApp'),style:FilledButton.styleFrom(backgroundColor:green))
 ])))));
}
Future<void> showLoanDetail(BuildContext context,Loan l) async {
 final m=getMember(l.memberId); if(m==null)return;
 await showModalBottomSheet(context:context,showDragHandle:true,builder:(c)=>Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
   Text(m.name,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900,color:navy)),Text(l.product),Text('Jatuh tempo: ${tanggal(l.dueDate)}'),Text('Tagihan: ${rupiah(l.amount)}'),Text('Sudah dibayar: ${rupiah(l.paid)}'),Text('Sisa: ${rupiah(l.remaining)}',style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:12),
   Wrap(spacing:8,children:[FilledButton.icon(onPressed:()=>sendWhatsApp(context,m,[l]),icon:const Icon(Icons.chat),label:const Text('WhatsApp')),OutlinedButton.icon(onPressed:()=>showCollectionForm(context,l),icon:const Icon(Icons.payments),label:const Text('Catat hasil'))])
 ])));
}
Future<void> sendWhatsApp(BuildContext context,Member m,List<Loan> loans) async {
 if(m.phone.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Nomor WhatsApp anggota belum tersedia.')));return;}
 final selected=loans.where((l)=>l.remaining>0).toList();
 final total=selected.fold(0.0,(s,l)=>s+l.remaining);
 final controller=TextEditingController(text:'Assalamu’alaikum ${m.name}.\\n\\nKami mengingatkan angsuran pembiayaan ${selected.map((l)=>l.product).toSet().join(', ')} dengan total tagihan ${rupiah(total)}. Mohon melakukan pembayaran sesuai jadwal. Jika sudah membayar, pesan ini dapat diabaikan.\\n\\nTerima kasih.\\nWassalamu’alaikum warahmatullahi wabarakatuh.');
 final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Pesan WhatsApp'),content:SizedBox(width:400,child:TextField(controller:controller,maxLines:9,decoration:const InputDecoration(border:OutlineInputBorder()))),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Buka WhatsApp'))]));
 if(ok==true){final uri=Uri.parse('https://wa.me/${cleanPhone(m.phone)}?text=${Uri.encodeComponent(controller.text)}');if(!await launchUrl(uri,mode:LaunchMode.externalApplication)&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('WhatsApp tidak dapat dibuka. Periksa nomor atau aplikasi WhatsApp.')));}
 controller.dispose();
}
Future<void> showCollectionForm(BuildContext context,Loan l) async {
 final m=getMember(l.memberId); if(m==null)return;
 String result='Berhasil membayar'; final paid=TextEditingController(); final note=TextEditingController();
 final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:Text('Catat penagihan • ${m.name}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
   DropdownButtonFormField<String>(value:result,decoration:const InputDecoration(labelText:'Hasil penagihan'),items:const ['Berhasil membayar','Pembayaran sebagian','Janji membayar','Belum bisa ditemui','Tidak ada pembayaran','Lainnya'].map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),onChanged:(v)=>setD(()=>result=v??result)),
   const SizedBox(height:10),TextField(controller:paid,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'Nominal diterima',helperText:'Sisa tagihan ${rupiah(l.remaining)}')),
   const SizedBox(height:10),TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Catatan / janji bayar')),
 ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Simpan'))])));
 if(ok==true){
   final amount=parseMoney(paid.text);
   if(amount>l.remaining){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Nominal melebihi sisa tagihan. Catatan tidak disimpan.')));}
   else {await store.addLog(l,result,amount,note.text.trim());if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Hasil penagihan disimpan.')));}
 }
 paid.dispose();note.dispose();
}
