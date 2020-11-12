using System.Collections;
using System.Collections.Generic;
using System.Text;
using UnityEngine;

[SLua.CustomLuaClass]
public class ForbidFilter
{
    protected static ForbidFilter _instance = null;
    public static ForbidFilter INSTANCE
    {
        get
        {
            if (_instance == null)
            {
                _instance = new ForbidFilter();
            }
            return _instance;
        }
    }

    internal class ForbidTreeNode
    {
        public Dictionary<char, ForbidTreeNode> nextForbidNodes;
        public string wholeForbidWord = "";
    }

    private Dictionary<char, ForbidTreeNode> forbidTree = new Dictionary<char, ForbidTreeNode>();
    private Dictionary<char, int> emptyWordMap = new Dictionary<char, int>();

    public void Init(SLua.LuaTable forbidWordTable, SLua.LuaTable emptyWordTable)
    {
        InitEmptyWord(emptyWordTable);
        Init(forbidWordTable);
    }

    public void InitEmptyWord(SLua.LuaTable emptyWordTable)
    {
        emptyWordMap.Clear();

        for (int i = 1; i <= emptyWordTable.length(); i++)
        {
            var word = emptyWordTable[i].ToString();
            if (word.Length == 1)
            {
                emptyWordMap.Add(word[0], 1);
            }
        }
    }

    public void Init(SLua.LuaTable forbidWordTable)
    {
        forbidTree.Clear();

        var forbidWordDic = forbidWordTable.ToDictionary<string, string>();
        foreach (KeyValuePair<string, string> word in forbidWordDic)
        {
            var wordCharArray = RevisionWord(word.Value.Trim()).ToCharArray();
            if (wordCharArray.Length <= 0)
            {
                continue;
            }

            ForbidTreeNode rootNode;
            if (forbidTree.ContainsKey(wordCharArray[0]))
            {
                rootNode = forbidTree[wordCharArray[0]];
            }
            else
            {
                rootNode = new ForbidTreeNode();
                forbidTree[wordCharArray[0]] = rootNode;
            }

            for (int i = 1; i < wordCharArray.Length; i++)
            {
                if (rootNode.nextForbidNodes != null && rootNode.nextForbidNodes.ContainsKey(wordCharArray[i]))
                {
                    rootNode = rootNode.nextForbidNodes[wordCharArray[i]];
                }
                else
                {
                    if (rootNode.nextForbidNodes == null)
                    {
                        rootNode.nextForbidNodes = new Dictionary<char, ForbidTreeNode>();
                    }

                    var nextNode = new ForbidTreeNode();
                    rootNode.nextForbidNodes[wordCharArray[i]] = nextNode;
                    rootNode = nextNode;
                }
            }
            rootNode.wholeForbidWord = word.Value;
        }
    }

    public void Reset()
    {
        forbidTree.Clear();
    }

    public bool CheckForbidWord(string checkWord, int index = 0)
    {
        if (checkWord.Length == 0 || index >= checkWord.Length)
        {
            return false;
        }

        if (!forbidTree.ContainsKey(checkWord[index]))
        {
            return CheckForbidWord(checkWord, index + 1);
        }

        var nextForbidTree = forbidTree[checkWord[index]];
        if (nextForbidTree.nextForbidNodes == null || nextForbidTree.wholeForbidWord.Length != 0)
        {
            return true;
        }

        var nextForbidNodes = nextForbidTree.nextForbidNodes;
        for (int i = index + 1; i < checkWord.Length; i++)
        {
            if (IsEmptyWord(checkWord[i]))
            {
                continue;
            }

            if (!nextForbidNodes.ContainsKey(checkWord[i]))
            {
                return CheckForbidWord(checkWord, index + 1);
            }

            var nextForbidNode = nextForbidNodes[checkWord[i]];
            if (nextForbidNode.nextForbidNodes == null || nextForbidNode.wholeForbidWord.Length != 0)
            {
                return true;
            }

            nextForbidNodes = nextForbidNode.nextForbidNodes;
        }

        return CheckForbidWord(checkWord, index + 1);
    }

    public string GetForbidWord(string checkWord, int index = 0, string forbidWord = "")
    {
        if (checkWord.Length == 0 || index >= checkWord.Length)
        {
            return forbidWord;
        }

        if (!forbidTree.ContainsKey(checkWord[index]))
        {
            return GetForbidWord(checkWord, index + 1, forbidWord);
        }

        var nextForbidTree = forbidTree[checkWord[index]];
        if (nextForbidTree.nextForbidNodes == null)
        {
            return nextForbidTree.wholeForbidWord;
        }

        if (nextForbidTree.wholeForbidWord.Length != 0)
        {
            forbidWord = nextForbidTree.wholeForbidWord;
        }

        var nextForbidNodes = nextForbidTree.nextForbidNodes;
        for (int i = index + 1; i < checkWord.Length; i++)
        {
            if (IsEmptyWord(checkWord[i]))
            {
                continue;
            }

            if (!nextForbidNodes.ContainsKey(checkWord[i]))
            {
                return GetForbidWord(checkWord, index + 1, forbidWord);
            }

            var nextForbidNode = nextForbidNodes[checkWord[i]];
            if (nextForbidNode.nextForbidNodes == null)
            {
                return checkWord.Substring(index, i - index + 1);
            }

            if (nextForbidNode.wholeForbidWord.Length != 0)
            {
                forbidWord = checkWord.Substring(index, i - index + 1);
            }

            nextForbidNodes = nextForbidNode.nextForbidNodes;
        }

        return GetForbidWord(checkWord, index + 1, forbidWord);
    }

    public string ReplaceForbidWord(string checkWord, string replaceWord, bool replaceEveryChar = false)
    {
        var forbidWord = GetForbidWord(checkWord);
        if (forbidWord.Length == 0)
        {
            return checkWord;
        }

        var realReplaceWord = replaceWord;
        if (replaceEveryChar)
        {
            StringBuilder builder = new StringBuilder();
            for (int i = 0; i < forbidWord.Length; i++)
            {
                builder.Append(replaceWord);
            }
            realReplaceWord = builder.ToString();
        }
        var modifyWord = checkWord.Replace(forbidWord, realReplaceWord);
        return ReplaceForbidWord(modifyWord, replaceWord, replaceEveryChar);
    }

    public bool IsEmptyWord(char word)
    {
        return emptyWordMap.ContainsKey(word);
    }

    private string RevisionWord(string word)
    {
        foreach(var key in emptyWordMap.Keys)
        {
            word = word.Replace(key.ToString(), "");
        }
        return word;
    }
}
