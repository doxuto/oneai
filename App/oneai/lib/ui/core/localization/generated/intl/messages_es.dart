// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a es locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'es';

  static String m0(count) => "Intento ${count}";

  static String m1(duration) => "Duración promedio: ${duration}ms";

  static String m2(count) => "Completadas: ${count}";

  static String m3(message) => "Error: ${message}";

  static String m4(title) => "¡Función ${title} próximamente!";

  static String m5(count) => "En progreso: ${count}";

  static String m6(path) => "Página no encontrada: ${path}";

  static String m7(id) => "ID de Publicación: ${id}";

  static String m8(count) => "Operaciones totales: ${count}";

  static String m9(id) => "ID de Usuario: ${id}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "appName": MessageLookupByLibrary.simpleMessage("One AI"),
    "appTitle": MessageLookupByLibrary.simpleMessage("One AI"),
    "attempt": m0,
    "audioIsDownloading": MessageLookupByLibrary.simpleMessage(
      "The audio is still being downloaded, please wait a moment.",
    ),
    "audioIsNotReady": MessageLookupByLibrary.simpleMessage(
      "The audio is not ready yet, please wait a moment.",
    ),
    "audioIsStartingDownload": MessageLookupByLibrary.simpleMessage(
      "The audio is starting to download, please wait a moment.",
    ),
    "autoDetect": MessageLookupByLibrary.simpleMessage("Detección automática"),
    "averageDuration": m1,
    "back": MessageLookupByLibrary.simpleMessage("Atrás"),
    "bengali": MessageLookupByLibrary.simpleMessage("Bengalí"),
    "breakTime": MessageLookupByLibrary.simpleMessage("Descanso"),
    "bulgarian": MessageLookupByLibrary.simpleMessage("Búlgaro"),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancelar"),
    "catalan": MessageLookupByLibrary.simpleMessage("Catalán"),
    "categories": MessageLookupByLibrary.simpleMessage("Categorías"),
    "categoriesComingSoon": MessageLookupByLibrary.simpleMessage(
      "Categorías - Próximamente",
    ),
    "categoriesDesc": MessageLookupByLibrary.simpleMessage(
      "Navegar por contenido por categorías.",
    ),
    "changeIcon": MessageLookupByLibrary.simpleMessage("Change Icon"),
    "chat": MessageLookupByLibrary.simpleMessage("Chat"),
    "chinese": MessageLookupByLibrary.simpleMessage("Chino"),
    "close": MessageLookupByLibrary.simpleMessage("Cerrar"),
    "comments": MessageLookupByLibrary.simpleMessage("Comentarios"),
    "commentsPlaceholder": MessageLookupByLibrary.simpleMessage(
      "Los comentarios se cargarían aquí en una aplicación real",
    ),
    "completed": m2,
    "confirmDeletion": MessageLookupByLibrary.simpleMessage(
      "Confirmar Eliminación",
    ),
    "create": MessageLookupByLibrary.simpleMessage("Crear"),
    "createNewTag": MessageLookupByLibrary.simpleMessage(
      "Crear Nueva Etiqueta",
    ),
    "createTag": MessageLookupByLibrary.simpleMessage("Crear etiqueta"),
    "croatian": MessageLookupByLibrary.simpleMessage("Croata"),
    "czech": MessageLookupByLibrary.simpleMessage("Checo"),
    "danish": MessageLookupByLibrary.simpleMessage("Danés"),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Tema oscuro"),
    "delete": MessageLookupByLibrary.simpleMessage("Eliminar"),
    "deleteNoteConfirmation": MessageLookupByLibrary.simpleMessage(
      "¿Estás seguro de que deseas eliminar esta nota? Esta acción no se puede deshacer.",
    ),
    "doneWithAi": MessageLookupByLibrary.simpleMessage("hechas\ncon IA"),
    "dutch": MessageLookupByLibrary.simpleMessage("Holandés"),
    "editIcon": MessageLookupByLibrary.simpleMessage("Editar Icono"),
    "editName": MessageLookupByLibrary.simpleMessage("Editar Nombre"),
    "english": MessageLookupByLibrary.simpleMessage("Inglés"),
    "enterNewIcon": MessageLookupByLibrary.simpleMessage(
      "Ingresa un nuevo icono",
    ),
    "enterNewName": MessageLookupByLibrary.simpleMessage(
      "Ingresa un nuevo nombre",
    ),
    "enterTagName": MessageLookupByLibrary.simpleMessage(
      "Ingresa un nombre para tu nueva etiqueta",
    ),
    "error": m3,
    "errorSharingContent": MessageLookupByLibrary.simpleMessage(
      "Error al compartir contenido. Inténtalo de nuevo.",
    ),
    "errorSharingPdf": MessageLookupByLibrary.simpleMessage(
      "Error al compartir PDF. Inténtalo de nuevo.",
    ),
    "estonian": MessageLookupByLibrary.simpleMessage("Estonio"),
    "featureComingSoon": m4,
    "featureUpdatesAndReleases": MessageLookupByLibrary.simpleMessage(
      "Actualizaciones y Lanzamientos",
    ),
    "finishingTouches": MessageLookupByLibrary.simpleMessage("Toques Finales"),
    "finnish": MessageLookupByLibrary.simpleMessage("Finlandés"),
    "flutterMvvmBlocDemo": MessageLookupByLibrary.simpleMessage(
      "Flutter MVVM BLoC Demostración",
    ),
    "french": MessageLookupByLibrary.simpleMessage("Francés"),
    "generatingPdf": MessageLookupByLibrary.simpleMessage("Generando PDF..."),
    "german": MessageLookupByLibrary.simpleMessage("Alemán"),
    "giveFeedback": MessageLookupByLibrary.simpleMessage("Dar Opinión"),
    "goHome": MessageLookupByLibrary.simpleMessage("Ir al Inicio"),
    "greek": MessageLookupByLibrary.simpleMessage("Griego"),
    "greetingNotes": MessageLookupByLibrary.simpleMessage("Notas de saludo"),
    "hebrew": MessageLookupByLibrary.simpleMessage("Hebreo"),
    "hindi": MessageLookupByLibrary.simpleMessage("Hindi"),
    "howDidWeDo": MessageLookupByLibrary.simpleMessage("¿Cómo lo hicimos?"),
    "hungarian": MessageLookupByLibrary.simpleMessage("Húngaro"),
    "identifyingSpeakers": MessageLookupByLibrary.simpleMessage(
      "Identificando Hablantes",
    ),
    "inProgress": m5,
    "indonesian": MessageLookupByLibrary.simpleMessage("Indonesio"),
    "instantNotesFromAudio": MessageLookupByLibrary.simpleMessage(
      "Notas instantáneas de\naudio y video, ",
    ),
    "irish": MessageLookupByLibrary.simpleMessage("Irlandés"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Tema claro"),
    "loadingStatistics": MessageLookupByLibrary.simpleMessage(
      "Estadísticas de Carga",
    ),
    "loadingStatisticsTooltip": MessageLookupByLibrary.simpleMessage(
      "Estadísticas de Carga",
    ),
    "manageTags": MessageLookupByLibrary.simpleMessage("Administrar Etiquetas"),
    "marketAndCompetitorInsights": MessageLookupByLibrary.simpleMessage(
      "Análisis de Mercado y Competencia",
    ),
    "mvvmBlocDemo": MessageLookupByLibrary.simpleMessage(
      "MVVM + BLoC Demostración",
    ),
    "newNote": MessageLookupByLibrary.simpleMessage("Nueva Nota"),
    "noNotesYet": MessageLookupByLibrary.simpleMessage("No hay notas aún"),
    "noUsersFound": MessageLookupByLibrary.simpleMessage(
      "No se encontraron usuarios",
    ),
    "oneAi": MessageLookupByLibrary.simpleMessage("One AI"),
    "openingAndKeyHighlight": MessageLookupByLibrary.simpleMessage(
      "Apertura y Puntos Clave",
    ),
    "pageNotFound": MessageLookupByLibrary.simpleMessage(
      "Página no encontrada",
    ),
    "pageNotFoundMessage": m6,
    "postId": m7,
    "posts": MessageLookupByLibrary.simpleMessage("Publicaciones"),
    "premium": MessageLookupByLibrary.simpleMessage("Premium"),
    "preparingContent": MessageLookupByLibrary.simpleMessage(
      "Preparando contenido...",
    ),
    "previouslySignedInWithApple": MessageLookupByLibrary.simpleMessage(
      "(Previamente iniciado sesión con Apple)",
    ),
    "processingAudio": MessageLookupByLibrary.simpleMessage("Procesando Audio"),
    "productRoadmapReview": MessageLookupByLibrary.simpleMessage(
      "Revisión de Hoja de Ruta",
    ),
    "promptAndLanguage": MessageLookupByLibrary.simpleMessage(
      "Mensaje e Idioma",
    ),
    "qAndAAndNextSteps": MessageLookupByLibrary.simpleMessage(
      "Preguntas y Próximos Pasos",
    ),
    "recordingContinue": MessageLookupByLibrary.simpleMessage(
      "Continuar grabación",
    ),
    "recordingPause": MessageLookupByLibrary.simpleMessage("Grabando pausa"),
    "recordingPaused": MessageLookupByLibrary.simpleMessage(
      "Grabación pausada",
    ),
    "recordingProcessingMessage": MessageLookupByLibrary.simpleMessage(
      "Para grabaciones más largas, esto podría tardar un minuto o dos.\nNo abandone la página.",
    ),
    "registered": MessageLookupByLibrary.simpleMessage("Registrado"),
    "rename": MessageLookupByLibrary.simpleMessage("Rename"),
    "resetLoadingStatesTooltip": MessageLookupByLibrary.simpleMessage(
      "Reiniciar Estados de Carga",
    ),
    "retry": MessageLookupByLibrary.simpleMessage("Reintentar"),
    "save": MessageLookupByLibrary.simpleMessage("Guardar"),
    "selectFile": MessageLookupByLibrary.simpleMessage("Seleccionar archivo"),
    "selectFileDescription": MessageLookupByLibrary.simpleMessage(
      "Seleccione un archivo de video o audio para transcripción y notas.",
    ),
    "selectIcon": MessageLookupByLibrary.simpleMessage("Select Icon"),
    "selectTheme": MessageLookupByLibrary.simpleMessage("Seleccionar tema"),
    "selectUserToViewPosts": MessageLookupByLibrary.simpleMessage(
      "Selecciona un usuario para ver publicaciones",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("seleccionado"),
    "settings": MessageLookupByLibrary.simpleMessage("Configuración"),
    "settingsComingSoon": MessageLookupByLibrary.simpleMessage(
      "Configuración - Próximamente",
    ),
    "settingsDesc": MessageLookupByLibrary.simpleMessage(
      "Opciones de configuración de la aplicación.",
    ),
    "share": MessageLookupByLibrary.simpleMessage("Compartir"),
    "shareAudioFile": MessageLookupByLibrary.simpleMessage(
      "Compartir archivo de audio",
    ),
    "shareNotesAsPdf": MessageLookupByLibrary.simpleMessage(
      "Compartir notas como PDF",
    ),
    "shareNotesAsText": MessageLookupByLibrary.simpleMessage(
      "Compartir notas como texto",
    ),
    "shareTranscriptAsPdf": MessageLookupByLibrary.simpleMessage(
      "Compartir transcripción como PDF",
    ),
    "shareTranscriptAsText": MessageLookupByLibrary.simpleMessage(
      "Compartir transcripción como texto",
    ),
    "signInWithApple": MessageLookupByLibrary.simpleMessage(
      "Iniciar sesión con Apple",
    ),
    "signInWithGoogle": MessageLookupByLibrary.simpleMessage(
      "Iniciar sesión con Google",
    ),
    "startAudioRecording": MessageLookupByLibrary.simpleMessage(
      "Iniciar grabación de audio",
    ),
    "systemTheme": MessageLookupByLibrary.simpleMessage("Tema del sistema"),
    "tabComingSoon": MessageLookupByLibrary.simpleMessage(
      "contenido de pestaña próximamente",
    ),
    "tagName": MessageLookupByLibrary.simpleMessage("Nombre de etiqueta"),
    "takingNotes": MessageLookupByLibrary.simpleMessage("Tomando Notas"),
    "tapButtonBelowToStart": MessageLookupByLibrary.simpleMessage(
      "Toca el botón de abajo para empezar",
    ),
    "tapToContinueRecording": MessageLookupByLibrary.simpleMessage(
      "Toca para continuar la grabación",
    ),
    "tapToStartRecording": MessageLookupByLibrary.simpleMessage(
      "Toca para comenzar la grabación",
    ),
    "tapToStopRecording": MessageLookupByLibrary.simpleMessage(
      "Toca para detener la grabación...",
    ),
    "teamUpdatesAndActionItems": MessageLookupByLibrary.simpleMessage(
      "Actualización del Equipo y Plan de Acción",
    ),
    "totalOperations": m8,
    "transcribeAndSummarize": MessageLookupByLibrary.simpleMessage(
      "Transcribir y Resumir",
    ),
    "transcribing": MessageLookupByLibrary.simpleMessage("Transcribiendo"),
    "transcript": MessageLookupByLibrary.simpleMessage("Transcripción"),
    "upgrade": MessageLookupByLibrary.simpleMessage("Mejorar"),
    "uploadFromFiles": MessageLookupByLibrary.simpleMessage(
      "Cargar desde archivos",
    ),
    "userId": m9,
    "users": MessageLookupByLibrary.simpleMessage("Usuarios"),
    "usersAndPosts": MessageLookupByLibrary.simpleMessage(
      "Usuarios y Publicaciones",
    ),
    "usersAndPostsDesc": MessageLookupByLibrary.simpleMessage(
      "Ver usuarios y sus publicaciones con gestión de estados de carga.",
    ),
    "welcomeMessage": MessageLookupByLibrary.simpleMessage(
      "Bienvenido a nuestra aplicación",
    ),
    "youTubeVideo": MessageLookupByLibrary.simpleMessage("Video de YouTube"),
    "youtubeUrlErrorMessage": MessageLookupByLibrary.simpleMessage(
      "Por favor introduzca una URL de YouTube válida",
    ),
    "youtubeUrlHint": MessageLookupByLibrary.simpleMessage(
      "Introduzca URL de YouTube",
    ),
    "youtubeVideoScreenTitle": MessageLookupByLibrary.simpleMessage(
      "Video de YouTube",
    ),
  };
}
