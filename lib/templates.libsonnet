{
  exe_to_pdb_path(binary):: (std.substr(binary, 0, std.length(binary) - 4) + '.pdb'),
  godot_tools_pipeline_export(
    pipeline_name='',
    pipeline_dependency='',
    gdextension_plugins=[],
    itchio_login='',
    gocd_group='',
    godot_status='',
    gocd_project_folder='',
    project_git='',
    project_branch='',
    enabled_export_platforms=[],
    vsk=true,
  )::
    {
      name: pipeline_name,
      group: gocd_group,
      label_template: godot_status + '.${' + pipeline_dependency + '_pipeline_dependency' + '}.${COUNT}',
      environment_variables:
        [{
          name: 'GODOT_STATUS',
          value: godot_status,
        }],
      materials: [
        {
          name: 'project_git_sandbox',
          url: project_git,
          type: 'git',
          branch: project_branch,
          destination: 'g',
        },
        {
          name: pipeline_dependency + '_pipeline_dependency',
          type: 'dependency',
          pipeline: pipeline_dependency,
          stage: 'templateZipStage',
          ignore_for_scheduling: false,
        },
      ] + [
        {
          name: library_info.pipeline_name + '_pipeline_dependency',
          type: 'dependency',
          pipeline: library_info.pipeline_name,
          stage: 'gdextensionBuildStage',
          ignore_for_scheduling: false,
        }
        for library_info in gdextension_plugins
      ],
      stages: [
        {
          name: 'exportStage',
          clean_workspace: false,
          fetch_materials: true,
          jobs: [
            {
              name: export_info.export_name + 'Job',
              resources: [
                'linux',
                'mingw5',
              ],
              artifacts: [
                {
                  type: 'build',
                  source: export_info.export_directory,
                  destination: '',
                },
              ],
              environment_variables:
                [],
              tasks: [
                {
                  type: 'fetch',
                  artifact_origin: 'gocd',
                  pipeline: pipeline_dependency,
                  stage: 'templateZipStage',
                  job: 'defaultJob',
                  is_source_a_file: true,
                  source: 'godot.templates.tpz',
                  destination: '',
                },
                {
                  type: 'fetch',
                  artifact_origin: 'gocd',
                  pipeline: pipeline_dependency,
                  stage: 'defaultStage',
                  job: 'linuxJob',
                  is_source_a_file: true,
                  source: 'godot.linuxbsd.opt.tools.x86_64.llvm',
                  destination: '',
                },
              ] + std.flatMap(function(library_info) [
                                {
                                  type: 'fetch',
                                  artifact_origin: 'gocd',
                                  pipeline: library_info.pipeline_name,
                                  stage: 'gdextensionBuildStage',
                                  job: export_info.gdextension_platform + 'Job',
                                  is_source_a_file: true,
                                  source: artifact,
                                  destination: library_info.name,
                                }
                                for artifact in library_info.platforms[export_info.gdextension_platform].output_artifacts
                              ],
                              gdextension_plugins) + std.flatMap(function(library_info) [
                                                                   if std.endsWith(artifact, '.dll') && artifact != 'openvr_api.dll' then {
                                                                     type: 'fetch',
                                                                     artifact_origin: 'gocd',
                                                                     pipeline: library_info.pipeline_name,
                                                                     stage: 'gdextensionBuildStage',
                                                                     job: export_info.gdextension_platform + 'Job',
                                                                     is_source_a_file: true,
                                                                     source: 'debug/' + self.exe_to_pdb_path(artifact),
                                                                     destination: library_info.name,
                                                                   } else null
                                                                   for artifact in library_info.platforms[export_info.gdextension_platform].output_artifacts
                                                                 ],
                                                                 gdextension_plugins) + [
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'rm -rf templates && unzip "godot.templates.tpz" && mkdir pdbs && mv templates/*.pdb pdbs && export VERSION="`cat templates/version.txt`" && export TEMPLATEDIR=".local/share/godot/export_templates/$VERSION/" && export HOME="`pwd`" && export BASEDIR="`pwd`" && rm -rf "$TEMPLATEDIR" && mkdir -p "$TEMPLATEDIR" && cd "$TEMPLATEDIR" && mv "$BASEDIR"/templates/* .',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
              ] + [
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    extra_task,
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                }
                for extra_task in export_info.prepare_commands
              ] + [
                if vsk then
                  {
                    type: 'exec',
                    arguments: [
                      '-c',
                      '(echo "## AUTOGENERATED BY BUILD"; echo ""; echo "const BUILD_LABEL = \\"$GO_PIPELINE_LABEL\\""; echo "const BUILD_DATE_STR = \\"$(date --utc --iso=seconds)\\""; echo "const BUILD_UNIX_TIME = $(date +%s)" ) > addons/vsk_version/build_constants.gd',
                    ],
                    command: '/bin/bash',
                    working_directory: 'g',
                  } else null,
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'rm -rf ' + export_info.export_directory + ' && mkdir -p g/.godot/editor && mkdir -p g/.godot/imported && mkdir ' + export_info.export_directory + ' && chmod +x ' + 'godot.linuxbsd.opt.tools.64.llvm' + ' && XDG_DATA_HOME=`pwd`/.local/share/ ./godot.linuxbsd.opt.tools.64.llvm --headless --export "' + export_info.export_configuration + '" "`pwd`/' + export_info.export_directory + '/' + export_info.export_executable + '" --path g || [ -f "`pwd`/' + export_info.export_directory + '/' + export_info.export_executable + '" ]',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
              ] + [
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    extra_task,
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                }
                for extra_task in export_info.extra_commands
              ],
            }
            for export_info in enabled_export_platforms
          ],
        },
        {
          name: 'uploadStage',
          clean_workspace: false,
          jobs: [
            {
              name: export_info.export_name + 'Job',
              resources: [
                'linux',
                'mingw5',
              ],
              tasks: [
                {
                  type: 'fetch',
                  artifact_origin: 'gocd',
                  pipeline: pipeline_name,
                  stage: 'exportStage',
                  job: export_info.export_name + 'Job',
                  is_source_a_file: false,
                  source: export_info.export_directory,
                  destination: '',
                },
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'echo push ' + export_info.export_directory + ' ' + itchio_login + ':' + export_info.itchio_out + ' --userversion $GO_PIPELINE_LABEL-`date --iso=seconds --utc`',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
              ],
            }
            for export_info in enabled_export_platforms
            if export_info.itchio_out != null
          ],
        },
      ],
    },
  build_docker_server(
    pipeline_name='',
    pipeline_dependency='',
    gocd_group='',
    godot_status='',
    docker_groups_git='',
    docker_groups_branch='',
    docker_groups_dir='',
    docker_repo_groups_server='',
    server_export_info={},
  )::
    {
      name: pipeline_name,
      group: gocd_group,
      label_template: '${' + pipeline_dependency + '_pipeline_dependency' + '}.${COUNT}',
      environment_variables:
        [],
      materials: [
        {
          name: 'docker_groups_git',
          url: docker_groups_git,
          type: 'git',
          branch: docker_groups_branch,
          destination: 'g',
        },
        {
          name: pipeline_dependency + '_pipeline_dependency',
          type: 'dependency',
          pipeline: pipeline_dependency,
          stage: 'exportStage',
          ignore_for_scheduling: false,
        },
      ],
      stages: [
        {
          name: 'buildPushStage',
          clean_workspace: false,
          fetch_materials: true,
          jobs: [
            {
              name: 'dockerJob',
              resources: [
                'dind',
              ],
              artifacts: [
                {
                  type: 'build',
                  source: 'docker_image.txt',
                  destination: '',
                },
              ],
              environment_variables: [
              ],
              tasks: [
                {
                  type: 'fetch',
                  artifact_origin: 'gocd',
                  pipeline: pipeline_dependency,
                  stage: 'exportStage',
                  job: server_export_info.export_name + 'Job',
                  is_source_a_file: false,
                  source: server_export_info.export_directory,
                  destination: 'g/' + docker_groups_dir,
                },
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'ls "g/' + docker_groups_dir + '"',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'chmod 01777 "g/' + docker_groups_dir + '/' + server_export_info.export_directory + '"',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'chmod a+x g/"' + docker_groups_dir + '/' + server_export_info.export_directory + '/' + server_export_info.export_executable + '"',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'docker build -t ' + docker_repo_groups_server + ':$GO_PIPELINE_LABEL' +
                    ' --build-arg SERVER_EXPORT="' + server_export_info.export_directory + '"' +
                    ' --build-arg GODOT_REVISION="master"' +
                    ' --build-arg USER=1234' +
                    ' --build-arg HOME=/server' +
                    ' --build-arg GROUPS_REVISION="$GO_PIPELINE_LABEL"' +
                    ' g/"' + docker_groups_dir + '"',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'docker push "' + docker_repo_groups_server + ':$GO_PIPELINE_LABEL"',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'echo "' + docker_repo_groups_server + ':$GO_PIPELINE_LABEL" > docker_image.txt',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
              ],
            },
          ],
        },
      ],
    },
  simple_docker_job(pipeline_name='',
                    gocd_group='',
                    docker_repo_variable='',
                    docker_git='',
                    docker_branch='',
                    docker_dir='')::
    {
      name: pipeline_name,
      group: gocd_group,
      label_template: pipeline_name + '_${' + pipeline_name + '_git[:8]}.${COUNT}',
      environment_variables:
        [],
      materials: [
        {
          name: pipeline_name + '_git',
          url: docker_git,
          type: 'git',
          branch: docker_branch,
          destination: 'g',
        },
      ],
      stages: [
        {
          name: 'buildPushStage',
          clean_workspace: false,
          fetch_materials: true,
          jobs: [
            {
              name: 'dockerJob',
              resources: [
                'dind',
              ],
              artifacts: [
                {
                  type: 'build',
                  source: 'docker_image.txt',
                  destination: '',
                },
              ],
              environment_variables:
                [],
              tasks: [
                {
                  type: 'exec',
                  arguments: [
                    '-c',
                    'set -x' +
                    '; docker build -t "' + docker_repo_variable + ':$GO_PIPELINE_LABEL"' +
                    ' "g/' + docker_dir + '" && docker push "' + docker_repo_variable + ':$GO_PIPELINE_LABEL"' +
                    ' && echo "' + docker_repo_variable + ':$GO_PIPELINE_LABEL" > docker_image.txt',
                  ],
                  command: '/bin/bash',
                  working_directory: '',
                },
              ],
            },
          ],
        },
      ],
    },
}
