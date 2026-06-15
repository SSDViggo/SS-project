// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../providers/camera_provider.dart';
// import '../screens/edit_screen.dart';

// class LibraryScreen extends StatelessWidget {
//   const LibraryScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         title: const Text('圖庫'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.more_vert),
//             onPressed: () {
//               // Show options
//             },
//           ),
//         ],
//       ),
//       body: Consumer<CameraProvider>(
//         builder: (context, cameraProvider, _) {
//           final photos = cameraProvider.capturedPhotos;

//           if (photos.isEmpty) {
//             return Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Icon(
//                     Icons.image_not_supported,
//                     size: 80,
//                     color: Colors.grey[700],
//                   ),
//                   const SizedBox(height: 16),
//                   Text(
//                     '還沒有圖片',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.grey[400],
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     '拍攝您的第一張照片開始',
//                     style: TextStyle(
//                       fontSize: 14,
//                       color: Colors.grey[600],
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           }

//           return GridView.builder(
//             padding: const EdgeInsets.all(12),
//             gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//               crossAxisCount: 3,
//               crossAxisSpacing: 8,
//               mainAxisSpacing: 8,
//             ),
//             itemCount: photos.length,
//             itemBuilder: (context, index) {
//               final path = photos[index];
//               return GestureDetector(
//                 onTap: () {
//                   Navigator.of(context).push(
//                     MaterialPageRoute(
//                       builder: (_) => EditScreen(imagePath: path),
//                     ),
//                   );
//                 },
//                 child: ClipRRect(
//                   borderRadius: BorderRadius.circular(8),
//                   child: Image.file(
//                     File(path),
//                     fit: BoxFit.cover,
//                     errorBuilder: (context, error, stackTrace) {
//                       return Container(
//                         color: Colors.grey[850],
//                         child: const Icon(Icons.broken_image, color: Colors.grey),
//                       );
//                     },
//                   ),
//                 ),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }