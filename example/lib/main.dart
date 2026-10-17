import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:snoop/snoop.dart';

// ---------------------------------------------------------------------------
// Wiring: the lines that matter are marked ①②③, plus the optional ④⑤.
// ---------------------------------------------------------------------------

void main() {
  Bloc.observer = SnoopBlocObserver(); // ①

  // The token is fake; it shows how redacted headers look in the Network tab.
  // Authorization, Cookie and Set-Cookie are redacted by default.
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://jsonplaceholder.typicode.com',
      headers: <String, Object?>{'Authorization': 'Bearer demo-secret-token'},
    ),
  );
  // replayClient: replays from the call detail page go through this same Dio.
  dio.interceptors.add(SnoopDioInterceptor(replayClient: dio)); // ②

  runApp(DemoApp(dio: dio));
}

class DemoApp extends StatelessWidget {
  const DemoApp({required this.dio, super.key});

  final Dio dio;

  @override
  Widget build(BuildContext context) => RepositoryProvider<Dio>.value(
    value: dio,
    child: MaterialApp(
      title: 'snoop demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      // ③ Mount the overlay above every route.
      builder: (context, child) => SnoopOverlay(child: child!),
      // ④ Optional: record navigation for the Routes tab.
      navigatorObservers: <NavigatorObserver>[SnoopRouteObserver()],
      home: const HomePage(),
    ),
  );
}

/// ⑤ Optional: feed your logger into the Logs tab.
void log(String message, {SnoopLogLevel level = SnoopLogLevel.info, Object? error}) =>
    Snoop.logs.log(message, level: level, source: 'PostsBloc', error: error);

// ---------------------------------------------------------------------------
// Blocs
// ---------------------------------------------------------------------------

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
  void decrement() => emit(state - 1);
}

class Post {
  const Post({required this.id, required this.title, required this.body});

  factory Post.fromJson(Map<String, dynamic> json) =>
      Post(id: json['id'] as int, title: json['title'] as String, body: json['body'] as String);

  final int id;
  final String title;
  final String body;

  // A toJson() lets the inspector show field names in the state tree.
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'title': title, 'body': body};
}

enum PostsStatus { initial, loading, success, failure }

class PostsState {
  const PostsState({this.status = PostsStatus.initial, this.posts = const <Post>[], this.error});

  final PostsStatus status;
  final List<Post> posts;
  final String? error;

  PostsState copyWith({PostsStatus? status, List<Post>? posts, String? error}) =>
      PostsState(status: status ?? this.status, posts: posts ?? this.posts, error: error);

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'posts': posts,
    'error': error,
  };

  @override
  String toString() => 'PostsState(${status.name}, ${posts.length} posts)';
}

sealed class PostsEvent {}

final class PostsRequested extends PostsEvent {
  PostsRequested({this.limit = 5});

  final int limit;

  @override
  String toString() => 'PostsRequested(limit: $limit)';
}

final class BrokenEndpointRequested extends PostsEvent {
  @override
  String toString() => 'BrokenEndpointRequested';
}

class PostsBloc extends Bloc<PostsEvent, PostsState> {
  PostsBloc(this._dio) : super(const PostsState()) {
    on<PostsRequested>(_onRequested);
    on<BrokenEndpointRequested>(_onBroken);
  }

  final Dio _dio;

  Future<void> _onRequested(PostsRequested event, Emitter<PostsState> emit) async {
    emit(state.copyWith(status: PostsStatus.loading));
    try {
      final response = await _dio.get<List<dynamic>>(
        '/posts',
        queryParameters: <String, Object?>{'_limit': event.limit},
      );
      final posts = response.data!
          .cast<Map<String, dynamic>>()
          .map(Post.fromJson)
          .toList(growable: false);
      emit(state.copyWith(status: PostsStatus.success, posts: posts));
      log('Loaded ${posts.length} posts');
    } on DioException catch (e, s) {
      log('Loading posts failed', level: SnoopLogLevel.error, error: e);
      addError(e, s);
      emit(state.copyWith(status: PostsStatus.failure, error: e.message));
    }
  }

  Future<void> _onBroken(BrokenEndpointRequested event, Emitter<PostsState> emit) async {
    emit(state.copyWith(status: PostsStatus.loading));
    try {
      await _dio.post<Object?>(
        '/this-route-does-not-exist',
        data: <String, Object?>{'hello': 'world'},
      );
    } on DioException catch (e, s) {
      log('Broken endpoint answered ${e.response?.statusCode}', level: SnoopLogLevel.error);
      addError(e, s);
      emit(state.copyWith(status: PostsStatus.failure, error: 'HTTP ${e.response?.statusCode}'));
    }
  }
}

// ---------------------------------------------------------------------------
// UI
// ---------------------------------------------------------------------------

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: <BlocProvider<Object?>>[
      BlocProvider<CounterCubit>(create: (_) => CounterCubit()),
      BlocProvider<PostsBloc>(
        create: (context) => PostsBloc(context.read<Dio>())..add(PostsRequested()),
      ),
    ],
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Inspector demo'),
        actions: <Widget>[
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Open Snoop',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => SnoopOverlay.open(context),
            ),
          ),
        ],
      ),
      body: const _Body(),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('Counter (a Cubit)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: context.read<CounterCubit>().decrement,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: BlocBuilder<CounterCubit, int>(
              builder: (context, count) => Text(
                '$count',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: context.read<CounterCubit>().increment,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const Divider(height: 32),
      Text('Posts (a Bloc using Dio)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          FilledButton.tonal(
            onPressed: () => context.read<PostsBloc>().add(PostsRequested(limit: 3)),
            child: const Text('Load 3'),
          ),
          FilledButton.tonal(
            onPressed: () => context.read<PostsBloc>().add(PostsRequested(limit: 10)),
            child: const Text('Load 10'),
          ),
          OutlinedButton(
            onPressed: () => context.read<PostsBloc>().add(BrokenEndpointRequested()),
            child: const Text('Call a 404'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      BlocBuilder<PostsBloc, PostsState>(
        builder: (context, state) => switch (state.status) {
          PostsStatus.initial || PostsStatus.loading => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          PostsStatus.failure => ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Request failed'),
            subtitle: Text('${state.error}. Open the inspector to see why.'),
          ),
          PostsStatus.success => Column(
            children: <Widget>[
              for (final post in state.posts)
                ListTile(
                  title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(post.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  // Tap: a pushed route with arguments (see the Routes tab).
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: RouteSettings(name: '/post', arguments: post.toJson()),
                      builder: (_) => PostPage(post: post),
                    ),
                  ),
                  // Long-press: the DTO as a tree, without leaving the screen.
                  onLongPress: () =>
                      showValueSheet(context: context, title: 'Post #${post.id}', value: post),
                ),
            ],
          ),
        },
      ),
    ],
  );
}

class PostPage extends StatelessWidget {
  const PostPage({required this.post, super.key});

  final Post post;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Post #${post.id}')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(post.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(post.body),
      ],
    ),
  );
}
