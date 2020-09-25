using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour
{
    public MetaBallField Field = new MetaBallField();
    
    private MeshFilter _filter;
    private Mesh _mesh;
    
    private List<Vector3> vertices = new List<Vector3>();
    private List<Vector3> normals = new List<Vector3>();
    private List<int> indices = new List<int>();

    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake()
    {
        // Getting a component, responsible for storing the mesh
        _filter = GetComponent<MeshFilter>();
        
        // instantiating the mesh
        _mesh = _filter.mesh = new Mesh();
        
        // Just a little optimization, telling unity that the mesh is going to be updated frequently
        _mesh.MarkDynamic();
    }

    /// <summary>
    /// Executed by Unity on every frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// You can use it to animate something in runtime.
    /// </summary>
    private void Update()
    {
        List<Vector3> cubeVertices = new List<Vector3>
        {
            new Vector3(0, 0, 0), // 0
            new Vector3(0, 1, 0), // 1
            new Vector3(1, 1, 0), // 2
            new Vector3(1, 0, 0), // 3
            new Vector3(0, 0, 1), // 4
            new Vector3(0, 1, 1), // 5
            new Vector3(1, 1, 1), // 6
            new Vector3(1, 0, 1), // 7
        };

        int[] sourceTriangles =
        {
            0, 1, 2, 2, 3, 0, // front
            3, 2, 6, 6, 7, 3, // right
            7, 6, 5, 5, 4, 7, // back
            0, 4, 5, 5, 1, 0, // left
            0, 3, 7, 7, 4, 0, // bottom
            1, 5, 6, 6, 2, 1, // top
        };

        
        vertices.Clear();
        indices.Clear();
        normals.Clear();
        
        Field.Update();
        // ----------------------------------------------------------------
        // Generate mesh here. Below is a sample code of a cube generation.
        // ----------------------------------------------------------------
        
        const float step = 0.2f;
        const float delta = 0.01f;
        var dx = new Vector3(delta, 0, 0);
        var dy = new Vector3(0, delta, 0);
        var dz = new Vector3(0, 0, delta);
        var leftDownCorner = new Vector3(-1.5f, -1.5f, -4);
        var smallCube = MarchingCubes.Tables._cubeVertices.Select(v => step * v + leftDownCorner).ToList();
        
        for (var xiter = 0; xiter <= 5 / step; xiter++)
        {
            for (var yiter = 0; yiter <= 5 / step; yiter++)
            {
                for (var ziter = 0; ziter <= 5 / step; ziter++)
                {
                    var offset = new Vector3(xiter * step, yiter * step, ziter * step);
                    var marchingCube = smallCube.Select(v => v + offset).ToArray();
                    var fv = marchingCube.Select(v => Field.F(v)).ToArray();
                    var mask = fv.Select(v => v >= 0).ToArray();
                    var caseNum = 0;
                    for (var i = 0; i < mask.Length; i++)
                    {
                        caseNum |= Convert.ToInt32(mask[i]) << i;
                    }
        
                    var triangleCount = MarchingCubes.Tables.CaseToTrianglesCount[caseNum];
                    for (var triangleNum = 0; triangleNum < triangleCount; triangleNum++)
                    {
                        var edges = MarchingCubes.Tables.CaseToVertices[caseNum][triangleNum];
                        for (var i = 0; i < 3; i++)
                        {
                            var edgeVertexes = MarchingCubes.Tables._cubeEdges[edges[i]];
                            var l = marchingCube[edgeVertexes[0]];
                            var r = marchingCube[edgeVertexes[1]];
                            
                            var fl = fv[edgeVertexes[0]];
                            var fr = fv[edgeVertexes[1]];

                            indices.Add(vertices.Count);
                            var t = - fl / (fr - fl);
                            var p = Vector3.Lerp(l, r, t);
                            vertices.Add(p);
                            var norm = - Vector3.Normalize(new Vector3(
                                Field.F(p + dx) - Field.F(p - dx),
                                Field.F(p + dy) - Field.F(p - dy),
                                Field.F(p + dz) - Field.F(p - dz)));
                            normals.Add(norm);
                        }
                    }
                }
            }
        }
        
        // What is going to happen if we don't split the vertices? Check it out by yourself by passing
        // sourceVertices and sourceTriangles to the mesh.
        // for (int i = 0; i < sourceTriangles.Length; i++)
        // {
        //     indices.Add(vertices.Count);
        //     Vector3 vertexPos = cubeVertices[sourceTriangles[i]];
        //     
        //     //Uncomment for some animation:
        //     //vertexPos += new Vector3
        //     //(
        //     //    Mathf.Sin(Time.time + vertexPos.z),
        //     //    Mathf.Sin(Time.time + vertexPos.y),
        //     //    Mathf.Sin(Time.time + vertexPos.x)
        //     //);
        //     
        //     vertices.Add(vertexPos);
        // }

        // Here unity automatically assumes that vertices are points and hence (x, y, z) will be represented as (x, y, z, 1) in homogenous coordinates
        _mesh.Clear();
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(indices, 0);
        _mesh.RecalculateNormals(); // Use _mesh.SetNormals(normals) instead when you calculate them
        _mesh.SetNormals(normals);
        
        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }
}