{ application, cuter, [
    {description, ""},
    {vsn, "1"},
    {registered, []},
    {modules, [cerl_pmatch,cuter_cerl,cuter_iserver,cuter_mock,cuter_symbolic,
               cuter_codeserver,cuter_json,cuter_monitor,cuter_types,
               cuter,cuter_debug,cuter_lib,cuter_poller,
               cuter_analyzer,cuter_env,cuter_log,cuter_pp,
               cuter_binlib,cuter_erlang,cuter_merger,cuter_scheduler_maxcover,
               cuter_callgraph,cuter_eval,cuter_minheap,cuter_solver]},
    {applications, [
        kernel,
        stdlib
    ]},
    {mod, {cuter, []}},
    {env, []}
]}.