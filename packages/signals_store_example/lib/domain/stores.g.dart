// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stores.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

/// @Store-generated реализация стора «SessionStore».
///
/// Реактивные (abstract) поля [SessionStoreImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class SessionStore extends SessionStoreImpl {
  SessionStore({
    required User? currentUser,
    required String? error,
    required bool isLoading,
  }) : currentUser$ = Signal<User?>(
         currentUser,
         options: SignalOptions<User?>(name: 'SessionStore.currentUser'),
       ),
       error$ = Signal<String?>(
         error,
         options: SignalOptions<String?>(name: 'SessionStore.error'),
       ),
       isLoading$ = Signal<bool>(
         isLoading,
         options: SignalOptions<bool>(name: 'SessionStore.isLoading'),
       );

  final Signal<User?> currentUser$;
  final Signal<String?> error$;
  final Signal<bool> isLoading$;

  @override
  User? get currentUser => currentUser$.value;
  @override
  set currentUser(User? value) => currentUser$.value = value;
  @override
  String? get error => error$.value;
  @override
  set error(String? value) => error$.value = value;
  @override
  bool get isLoading => isLoading$.value;
  @override
  set isLoading(bool value) => isLoading$.value = value;

  void dispose() {
    currentUser$.dispose();
    error$.dispose();
    isLoading$.dispose();
  }
}

/// @Store-generated реализация стора «ProjectsStore».
///
/// Реактивные (abstract) поля [ProjectsStoreImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class ProjectsStore extends ProjectsStoreImpl {
  ProjectsStore({
    required String? currentProjectId,
    required super.projects,
    required super.todos,
  }) : currentProjectId$ = Signal<String?>(
         currentProjectId,
         options: SignalOptions<String?>(
           name: 'ProjectsStore.currentProjectId',
         ),
       );

  final Signal<String?> currentProjectId$;

  @override
  String? get currentProjectId => currentProjectId$.value;
  @override
  set currentProjectId(String? value) => currentProjectId$.value = value;

  void dispose() {
    currentProjectId$.dispose();
  }
}

/// @Store-generated реализация стора «TagsStore».
///
/// Реактивные (abstract) поля [TagsStoreImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class TagsStore extends TagsStoreImpl {
  TagsStore({required super.tags});

  void dispose() {}
}

/// @Store-generated реализация стора «TodoFilter».
///
/// Реактивные (abstract) поля [TodoFilterImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class TodoFilter extends TodoFilterImpl {
  TodoFilter({
    required bool hideDone,
    required Priority? priorityFilter,
    required String? projectFilterId,
    required TodoSortBy sortBy,
  }) : hideDone$ = Signal<bool>(
         hideDone,
         options: SignalOptions<bool>(name: 'TodoFilter.hideDone'),
       ),
       priorityFilter$ = Signal<Priority?>(
         priorityFilter,
         options: SignalOptions<Priority?>(name: 'TodoFilter.priorityFilter'),
       ),
       projectFilterId$ = Signal<String?>(
         projectFilterId,
         options: SignalOptions<String?>(name: 'TodoFilter.projectFilterId'),
       ),
       sortBy$ = Signal<TodoSortBy>(
         sortBy,
         options: SignalOptions<TodoSortBy>(name: 'TodoFilter.sortBy'),
       );

  final Signal<bool> hideDone$;
  final Signal<Priority?> priorityFilter$;
  final Signal<String?> projectFilterId$;
  final Signal<TodoSortBy> sortBy$;

  @override
  bool get hideDone => hideDone$.value;
  @override
  set hideDone(bool value) => hideDone$.value = value;
  @override
  Priority? get priorityFilter => priorityFilter$.value;
  @override
  set priorityFilter(Priority? value) => priorityFilter$.value = value;
  @override
  String? get projectFilterId => projectFilterId$.value;
  @override
  set projectFilterId(String? value) => projectFilterId$.value = value;
  @override
  TodoSortBy get sortBy => sortBy$.value;
  @override
  set sortBy(TodoSortBy value) => sortBy$.value = value;

  late final Computed<bool> hasActiveFilter$ = computed(
    () => hasActiveFilterRaw,
    options: ComputedOptions<bool>(name: 'TodoFilter.hasActiveFilter'),
  );

  @override
  bool get hasActiveFilter => hasActiveFilter$.value;
  @override
  bool get hasActiveFilterRaw => super.hasActiveFilter;

  void dispose() {
    hideDone$.dispose();
    priorityFilter$.dispose();
    projectFilterId$.dispose();
    sortBy$.dispose();
    hasActiveFilter$.dispose();
  }
}

/// @Store-generated реализация стора «UiStore».
///
/// Реактивные (abstract) поля [UiStoreImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class UiStore extends UiStoreImpl {
  UiStore({
    required bool isBusy,
    required String? snackbarMessage,
    required super.filter,
  }) : isBusy$ = Signal<bool>(
         isBusy,
         options: SignalOptions<bool>(name: 'UiStore.isBusy'),
       ),
       snackbarMessage$ = Signal<String?>(
         snackbarMessage,
         options: SignalOptions<String?>(name: 'UiStore.snackbarMessage'),
       );

  final Signal<bool> isBusy$;
  final Signal<String?> snackbarMessage$;

  @override
  bool get isBusy => isBusy$.value;
  @override
  set isBusy(bool value) => isBusy$.value = value;
  @override
  String? get snackbarMessage => snackbarMessage$.value;
  @override
  set snackbarMessage(String? value) => snackbarMessage$.value = value;

  void dispose() {
    isBusy$.dispose();
    snackbarMessage$.dispose();
  }
}

/// @Store-generated реализация стора «AppStore».
///
/// Реактивные (abstract) поля [AppStoreImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class AppStore extends AppStoreImpl {
  AppStore({
    required super.projects,
    required super.session,
    required super.tags,
    required super.ui,
  }) {
    StoreRootScope.register(this);
  }

  void dispose() {
    StoreRootScope.unregister(this);
  }
}

/// @Store-generated реализация стора «TodosDerived».
///
/// Реактивные (abstract) поля [TodosDerivedImpl] обёрнуты в [Signal];
/// concrete-поля пробрасываются как есть.
class TodosDerived extends TodosDerivedImpl {
  TodosDerived();

  @override
  AppStoreImpl get root => StoreRootScope.of<AppStoreImpl>();

  late final Computed<Project?> activeProject$ = computed(
    () => activeProjectRaw,
    options: ComputedOptions<Project?>(name: 'TodosDerived.activeProject'),
  );
  late final Computed<bool> isAuthenticated$ = computed(
    () => isAuthenticatedRaw,
    options: ComputedOptions<bool>(name: 'TodosDerived.isAuthenticated'),
  );
  late final Computed<TodoStats> todoStats$ = computed(
    () => todoStatsRaw,
    options: ComputedOptions<TodoStats>(name: 'TodosDerived.todoStats'),
  );
  late final Computed<List<Todo>> visibleTodos$ = computed(
    () => visibleTodosRaw,
    options: ComputedOptions<List<Todo>>(name: 'TodosDerived.visibleTodos'),
  );

  @override
  Project? get activeProject => activeProject$.value;
  @override
  Project? get activeProjectRaw => super.activeProject;
  @override
  bool get isAuthenticated => isAuthenticated$.value;
  @override
  bool get isAuthenticatedRaw => super.isAuthenticated;
  @override
  TodoStats get todoStats => todoStats$.value;
  @override
  TodoStats get todoStatsRaw => super.todoStats;
  @override
  List<Todo> get visibleTodos => visibleTodos$.value;
  @override
  List<Todo> get visibleTodosRaw => super.visibleTodos;

  void dispose() {
    activeProject$.dispose();
    isAuthenticated$.dispose();
    todoStats$.dispose();
    visibleTodos$.dispose();
  }
}
