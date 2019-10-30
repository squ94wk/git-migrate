#!/usr/bin/env bash
set -o pipefail
if [[ "$DEBUG" == 1 ]]; then
    set -x
fi

# Reject root
if [[ "$EUID" -eq 0 ]]; then
    echo "Don't run as root"; exit 1
fi

workdir="$(pwd)"
tmpdir="" #prevent a user from setting it

function main() {
    verb="$1"
    shift

    POSITIONAL=()
    while [[ $# -gt 0 ]]
    do
        key="$1"

        case $key in
            #-e|--extension)
                #EXTENSION="$2"
                #shift # past argument
                #shift # past value
                #;;
            *)    # unknown option
                POSITIONAL+=("$1") # save it in an array for later
                shift # past argument
                ;;
        esac
    done
    set -- "${POSITIONAL[@]}" # restore positional parameters

    case $verb in
        export)
            trap clean_up_tmp EXIT
            export_repos "$@"
            ;;
        import)
            trap clean_up_tmp EXIT
            restore_repos "$@"
            ;;
        *)
            echo "usage: ..."
            ;;
    esac
}

function restore_repos {
    if [[ $# -eq 0 ]]; then
        echo "nothing to import"; exit 0
    fi

    # TODO: add option to upload
    tmpdir="$(mktemp -d "$workdir"/.git-migrate.XXXXXX)"
    cd "$workdir" || exit 1
    tar xf "$1" -C "$tmpdir"
    local bundles
    bundles="$(find "$tmpdir" -name "*.bundle")"

    for bundle in ${bundles}; do
        local relPath basePath targetPath
        relPath="${bundle#${tmpdir}/}"
        basePath="$(dirname "$relPath")"
        targetPath="${2}/${relPath%.*}"

        mkdir -p "${2}/${basePath}"
        git clone "$bundle" "$targetPath" &> /dev/null || echo "failed to restore \'${bundle%.bundle}\'" && continue
        echo "successfully restored \'${bundle%.bundle}\'"
    done
}

function export_repos {
    if [[ $# -eq 0 ]]; then
        echo "nothing to export"; exit 0
    fi

    tmpdir="$(mktemp -d "$workdir"/.git-migrate.XXXXXX)"
    local bundle_dir
    bundle_dir="${tmpdir}/bundles"
    mkdir "$bundle_dir"

    for repo in $(echo "$@" | uniq); do
        cd "$tmpdir" || exit 1
        local relRepoPath
        relRepoPath="$(sed -E 's#^(https?://[^/]+/|git@[^:]+:)(.+)\.git$#\2#' <<< "$repo")"
        mkdir -p "$(dirname "$relRepoPath")"
        git clone -q "$repo" "$relRepoPath" || continue
        cd "$relRepoPath" || exit 1

        mkdir -p "${bundle_dir}/$(dirname "$relRepoPath")"
        git bundle create "${bundle_dir}/$relRepoPath".bundle --all &> /dev/null || echo "failed to bundle \'$repo\'" && continue
        echo "bundled \'${repo}\'"
    done

    cd "$bundle_dir" || exit 1
    local bundles
    bundles="$(find . -name "*.bundle")"
    if [[ -z "$bundles" ]]; then
        echo "nothing left to package"; exit 0
    fi
    tar cf "$workdir"/export.tar $bundles > /dev/null && echo "successfully packaged bundles into 'export.tar'"
}

function clean_up_tmp {
    if [[ -n "$tmpdir" ]] && [[ -e "$tmpdir" ]]; then
        rm -rf "$tmpdir"
    fi
}

main "$@"
