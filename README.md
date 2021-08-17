# Puppet Community MVP tool

This is a simple tool to generate stats about the Puppet community. It was
originally intended to show the "most valuable players" but has since morphed to
show a lot of other things too. We primarily use it on a weekly cron job to
gather information using the Forge APIs and normalizing them so that they can be
easily combined with simple SQL queries to generate usage information.

## Interactive usage

If you're not working on our community stats pipeline, then there are only three
subcommands you'll be interested in.

### `stats`

This subcommand will use cached data to generate a report of Forge community
statistics. For example, it will generate distributions of module quality
scores, or releases per module, or modules per author, etc. And it will generate
sparklines showing the contributions over time of the most prolific Forge
authors and it will show authors who aren't as active as they used to be.

Unfortunately, this report is not customizable or templatable at this point.

You will need cached data before you can generate this report. See the `get` subcommand.


### `get`

This subcommand will download and cache a local mirror of the data stored in our
BigQuery database. This data is used for the `stats` command.


### `analyze`

This subcommand is maybe the most interesting. Many interesting bits of
information can be gathered by inspecting the source code of modules, not by
running SQL queries about their statistics. For example, `find manifests/ -name
'*.pp' | wc -l` will tell you how many manifests any given module includes, and
`grep -rn '--no-external-facts' facts.d/` will tell you how many external facts
are invoking `facter` to gather and use _other_ facts while running.

This command lets you write that little bit of analysis code as a script, and
then systematically run that script against the current release of every single
module on the Forge and collate the generated output.

A script can be written in any language and will be executed from the root of
the unpacked module. It will be invoked with an environment containing the following
variables:

* `mvp_owner` -- the Forge namespace of the module, aka the author's username
* `mvp_name` -- the name of the module itself
* `mvp_version` -- the current version of the module
* `mvp_downloads` -- the number of downloads this module has. A *rough* estimation of popularity

The script should print an array of arrays in JSON format to STDOUT. These will be
combined to make a CSV file, the columns of which are defined by the data you
return. In other words, the items in the inner array(s) are totally up to you.
They will become the columns of the generated CSV file.

The parameters relevant to this subcommand are:

```
    -o, --output_file OUTPUT_FILE    The path to save a csv report.
        --script SCRIPT              The script file to analyze a module. See docs for interface.
        --count N                    For debugging. Select a random list of this many modules to analyze.
    -d, --debug                      Display extra debugging information.
```

See files in the `scripts/` directory for examples of analysis scripts. To use,
just path of a script, like

```
$ mvp analyze --script scripts/manifest_count.rb --count 5
[✔] stdlib (OK)
$ cat analyzed.csv
...
```

