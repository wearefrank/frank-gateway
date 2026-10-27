# Merge config Plugin

## Description:
Allows for the use of multiple config files for the Frank!Gateway. Upon startup of the gateway it will dynamically merge them together for the runtime.   

## Features:
- Allows for functional seperation of apisix configurations
- Checks for duplicate sections, gives an error if any are present 
- Rebuild the configuration if any changes are detected


## Requirements:

## Behavior: 
Starts the build function on startup.
retrieves all files inside the input directory. 
Lists all sections and checks for any duplicate entries. 
Merges the files together and writes to the output file 
Runs a check every X seconds on the files in the input directory, if any change is detected reruns the build process

## Known issues:

## Configuration:

### Plugin Metadata: 
Name: merge-config
Type: generic 
Priority: 1

### Plugin Schema

| Property                    | Type            | Required | Default                   | Description                                 |
|-----------------------------|-----------------|----------|---------------------------|---------------------------------------------|
| <NameOfField>             | <Type>        | <Required>| <DefaultValue>       | <Description>            |
|input_directory | String | No | /usr/local/apisix/conf/mergeconfigs | The input directory for the to be merged configs | 
|output_file | String | No | /usr/local/apisix/conf/apisix.yaml | the output location of the apisix.yaml| 
|section_order | Array | No | "ssls", "consumers", "consumer_groups", "services", "routes","stream_routes", "upstreams", "global_rules", "plugin_configs","plugin_metadata", "secrets"| The order the segments will be written in the output file | 
|interval | Integer | No |  2 | How often (in seconds) to check for changes and rebuild|
|enabled | Boolean | No | False | enables the merge plugin |  

### Configuration example
```yaml 
plugin_attr:
  merge-config:
    enabled: true
    interval: 2
    input_directory: "/usr/local/apisix/conf/mergeconfigs"
    output_file: "/usr/local/apisix/conf/apisix.yaml"

```

### Configuration specifics 
Can only be configured in the config.yaml 
## Examples 