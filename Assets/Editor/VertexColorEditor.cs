using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

public class VertexColorEditor : EditorWindow
{
    // UV7 is used to store stable per-vertex group IDs on duplicated mesh assets.
    // This lets groups survive color edits that cause two groups to share the same value.
    private const int GroupUVChannel = 7;

    private GameObject _selectedGO;
    private readonly List<Color> _uniqueColors = new();
    private readonly List<List<int>> _colorVertexIndices = new();
    private Vector2 _scroll;

    [MenuItem("Tools/Vertex Color Editor")]
    private static void Open() => GetWindow<VertexColorEditor>("Vertex Colors");

    private void OnEnable()
    {
        Selection.selectionChanged += OnSelectionChanged;
        OnSelectionChanged();
    }

    private void OnDisable()
    {
        Selection.selectionChanged -= OnSelectionChanged;
    }

    private void OnSelectionChanged()
    {
        _selectedGO = Selection.activeGameObject;
        RefreshColors();
        Repaint();
    }

    private void RefreshColors()
    {
        _uniqueColors.Clear();
        _colorVertexIndices.Clear();

        Mesh mesh = GetMesh(_selectedGO);
        if (mesh == null || mesh.colors.Length == 0)
            return;

        Color[] colors = mesh.colors;

        var groupUVs = new List<Vector4>();
        mesh.GetUVs(GroupUVChannel, groupUVs);
        bool hasGroupData = groupUVs.Count == mesh.vertexCount;

        if (hasGroupData)
        {
            // Group by stable UV7 group ID — survives color edits
            var groupIdToSlot = new Dictionary<int, int>();
            for (int i = 0; i < colors.Length; i++)
            {
                int groupId = Mathf.RoundToInt(groupUVs[i].x);
                if (!groupIdToSlot.TryGetValue(groupId, out int slot))
                {
                    slot = _uniqueColors.Count;
                    groupIdToSlot[groupId] = slot;
                    _uniqueColors.Add(colors[i]);
                    _colorVertexIndices.Add(new List<int>());
                }
                _colorVertexIndices[slot].Add(i);
            }
        }
        else
        {
            // Fall back to color-based grouping (read-only imported meshes)
            var colorToSlot = new Dictionary<Color, int>();
            for (int i = 0; i < colors.Length; i++)
            {
                if (!colorToSlot.TryGetValue(colors[i], out int slot))
                {
                    slot = _uniqueColors.Count;
                    colorToSlot[colors[i]] = slot;
                    _uniqueColors.Add(colors[i]);
                    _colorVertexIndices.Add(new List<int>());
                }
                _colorVertexIndices[slot].Add(i);
            }
        }
    }

    private static Mesh GetMesh(GameObject go)
    {
        if (go == null) return null;

        if (go.TryGetComponent<MeshFilter>(out var mf)) return mf.sharedMesh;
        if (go.TryGetComponent<SkinnedMeshRenderer>(out var smr)) return smr.sharedMesh;

        return null;
    }

    private void OnGUI()
    {
        if (_selectedGO == null)
        {
            EditorGUILayout.HelpBox("Select a GameObject with a MeshFilter or SkinnedMeshRenderer.", MessageType.Info);
            return;
        }

        Mesh mesh = GetMesh(_selectedGO);

        if (mesh == null)
        {
            EditorGUILayout.HelpBox($"{_selectedGO.name} has no mesh.", MessageType.Warning);
            return;
        }

        if (mesh.colors.Length == 0)
        {
            EditorGUILayout.HelpBox($"{_selectedGO.name}'s mesh has no vertex colors.", MessageType.Warning);
            return;
        }

        EditorGUILayout.LabelField(_selectedGO.name, EditorStyles.boldLabel);
        EditorGUILayout.LabelField($"{_uniqueColors.Count} unique color(s) across {mesh.colors.Length} vertices");
        EditorGUILayout.Space();

        bool editable = IsMeshEditable(mesh);
        if (!editable)
            EditorGUILayout.HelpBox("Mesh is read-only (imported asset). Duplicate it to edit colors.", MessageType.Info);

        _scroll = EditorGUILayout.BeginScrollView(_scroll);

        using (new EditorGUI.DisabledScope(!editable))
        {
            for (int i = 0; i < _uniqueColors.Count; i++)
            {
                EditorGUI.BeginChangeCheck();
                Color newColor = EditorGUILayout.ColorField($"Group {i}", _uniqueColors[i]);
                if (EditorGUI.EndChangeCheck())
                {
                    ApplyColorChange(mesh, _colorVertexIndices[i], newColor);
                    _uniqueColors[i] = newColor;
                }
            }
        }

        EditorGUILayout.EndScrollView();

        EditorGUILayout.Space();
        if (GUILayout.Button("Duplicate Mesh to Asset & Apply"))
            DuplicateMeshAsset(_selectedGO);
    }

    private static bool IsMeshEditable(Mesh mesh)
    {
        string path = AssetDatabase.GetAssetPath(mesh);
        if (string.IsNullOrEmpty(path)) return false;
        return AssetImporter.GetAtPath(path) is not ModelImporter;
    }

    private static void ApplyColorChange(Mesh mesh, List<int> vertexIndices, Color newColor)
    {
        Color[] colors = mesh.colors;
        Undo.RecordObject(mesh, "Edit Vertex Color");
        foreach (int idx in vertexIndices)
            colors[idx] = newColor;
        mesh.colors = colors;
        EditorUtility.SetDirty(mesh);
    }

    // Assigns a stable integer group ID (stored in UV7.x) to each vertex based on
    // its current color. Called once when a mesh is first duplicated as an asset.
    private static void InitializeGroupData(Mesh mesh)
    {
        Color[] colors = mesh.colors;
        var colorToGroup = new Dictionary<Color, int>();
        var groupIds = new Vector4[colors.Length];

        for (int i = 0; i < colors.Length; i++)
        {
            if (!colorToGroup.TryGetValue(colors[i], out int group))
            {
                group = colorToGroup.Count;
                colorToGroup[colors[i]] = group;
            }
            groupIds[i] = new Vector4(group, 0f, 0f, 0f);
        }

        mesh.SetUVs(GroupUVChannel, groupIds);
    }

    private static void DuplicateMeshAsset(GameObject go)
    {
        Mesh source = GetMesh(go);
        if (source == null) return;

        string path = EditorUtility.SaveFilePanelInProject(
            "Save Mesh Asset",
            source.name + "_Copy",
            "asset",
            "Choose where to save the duplicated mesh.");

        if (string.IsNullOrEmpty(path)) return;

        Mesh copy = Object.Instantiate(source);
        copy.name = Path.GetFileNameWithoutExtension(path);

        InitializeGroupData(copy);

        AssetDatabase.CreateAsset(copy, path);
        AssetDatabase.SaveAssets();

        if (go.TryGetComponent<MeshFilter>(out var mf))
        {
            Undo.RecordObject(mf, "Apply Duplicated Mesh");
            mf.sharedMesh = copy;
        }
        else if (go.TryGetComponent<SkinnedMeshRenderer>(out var smr))
        {
            Undo.RecordObject(smr, "Apply Duplicated Mesh");
            smr.sharedMesh = copy;
        }

        if (go.TryGetComponent<MeshCollider>(out var mc))
        {
            Undo.RecordObject(mc, "Apply Duplicated Mesh");
            mc.sharedMesh = copy;
        }

        EditorGUIUtility.PingObject(copy);
    }
}
