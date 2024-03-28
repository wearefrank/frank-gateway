# Frank Gateway Dashboard build
The Frank Gateway dashboard is based on the [APISIX Dashboard](https://github.com/apache/apisix-dashboard) with the following customizations:
- We Are Frank theme
- FSC plugin configuration form

To create a build of the Frank API Gateway Dashboard:
1. make changes to the APISIX Dashboard project
2. run `make build`
3. copy the folders `output/conf`, `output/dag-to-lua` and `output/html` to the 'output' directory in this current directory
4. run `make dashboard-build -C ../..`
`note, the -C ../.. is only required when issuing the command from the directory where this README resides`
